@testable import AppBundle
import CoreGraphics
import XCTest

final class WindowShakeGestureTest: XCTestCase {
    func testRecognizesFourDeliberateHorizontalStrokes() {
        var gesture = WindowShakeGestureRecognizer()

        XCTAssertFalse(gesture.observe(sample(0, 0.00)))
        XCTAssertFalse(gesture.observe(sample(65, 0.12)))
        XCTAssertFalse(gesture.observe(sample(0, 0.24)))
        XCTAssertFalse(gesture.observe(sample(65, 0.36)))
        XCTAssertTrue(gesture.observe(sample(0, 0.48)))
        XCTAssertFalse(gesture.observe(sample(65, 0.60)), "A gesture only fires once per drag")
    }

    func testRejectsOrdinaryDragWithSmallDirectionCorrections() {
        var gesture = WindowShakeGestureRecognizer()

        for (index, x) in [0, 30, 28, 80, 76, 140, 136, 210].enumerated() {
            XCTAssertFalse(gesture.observe(sample(CGFloat(x), Double(index) * 0.08)))
        }
    }

    func testRejectsVerticalDominantMovement() {
        var gesture = WindowShakeGestureRecognizer()

        for (index, point) in [
            CGPoint(x: 0, y: 0), CGPoint(x: 65, y: 80), CGPoint(x: 0, y: 160),
            CGPoint(x: 65, y: 240), CGPoint(x: 0, y: 320),
        ].enumerated() {
            XCTAssertFalse(gesture.observe(MousePointerSample(point: point, timestamp: Double(index) * 0.1)))
        }
    }

    func testLongPauseResetsGestureWindow() {
        var gesture = WindowShakeGestureRecognizer()

        XCTAssertFalse(gesture.observe(sample(0, 0.00)))
        XCTAssertFalse(gesture.observe(sample(65, 0.10)))
        XCTAssertFalse(gesture.observe(sample(0, 0.20)))
        XCTAssertFalse(gesture.observe(sample(65, 0.70)))
        XCTAssertFalse(gesture.observe(sample(0, 0.80)))
        XCTAssertFalse(gesture.observe(sample(65, 0.90)))
    }

    func testOnlyDirectWindowMoveSessionsCanRecognizeShake() {
        XCTAssertTrue(shouldRecognizeWindowShake(
            kind: .move,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: false,
            isPointerInsideSidebar: false,
        ))
        XCTAssertFalse(shouldRecognizeWindowShake(
            kind: .resize,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: false,
            isPointerInsideSidebar: false,
        ))
        XCTAssertFalse(shouldRecognizeWindowShake(
            kind: .move,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: false,
            isPointerInsideSidebar: false,
        ))
        XCTAssertFalse(shouldRecognizeWindowShake(
            kind: .move,
            subject: .window,
            detachOrigin: .tabStrip,
            startedInSidebar: false,
            isPointerInsideSidebar: false,
        ))
        XCTAssertFalse(shouldRecognizeWindowShake(
            kind: .move,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: true,
            isPointerInsideSidebar: false,
        ))
        XCTAssertFalse(shouldRecognizeWindowShake(
            kind: .move,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: false,
            isPointerInsideSidebar: true,
        ))
    }

    private func sample(_ x: CGFloat, _ timestamp: TimeInterval) -> MousePointerSample {
        MousePointerSample(point: CGPoint(x: x, y: 100), timestamp: timestamp)
    }
}

@MainActor
final class WindowShakeLayoutToggleTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
    }

    func testShakeToggleRestoresSurvivingTilingPlacement() {
        let workspace = focus.workspace
        let left = TestWindow.new(id: 801, parent: workspace.rootTilingContainer)
        let shaken = TestWindow.new(id: 802, parent: workspace.rootTilingContainer)
        let right = TestWindow.new(id: 803, parent: workspace.rootTilingContainer)
        let driver = WindowMouseInteractionDriver.shared

        driver.toggleFloatingForShake(shaken)
        XCTAssertTrue(shaken.isFloating)
        XCTAssertEqual(workspace.rootTilingContainer.children, [left, right])

        driver.toggleFloatingForShake(shaken)
        XCTAssertFalse(shaken.isFloating)
        XCTAssertEqual(workspace.rootTilingContainer.children, [left, shaken, right])
    }

    func testShakeRetileFallsBackWhenOriginalContainerWasRemoved() {
        let workspace = focus.workspace
        let nested = TilingContainer(
            parent: workspace.rootTilingContainer,
            adaptiveWeight: 1,
            .h,
            .tiles,
            index: INDEX_BIND_LAST,
        )
        let shaken = TestWindow.new(id: 804, parent: nested)
        let driver = WindowMouseInteractionDriver.shared

        driver.toggleFloatingForShake(shaken)
        nested.unbindFromParent()
        driver.toggleFloatingForShake(shaken)

        XCTAssertFalse(shaken.isFloating)
        XCTAssertTrue(shaken.nodeWorkspace === workspace)
        XCTAssertFalse(shaken.parent === nested)
    }
}
