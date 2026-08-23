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
        config.workspaceSidebar.enabled = false
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

    func testShakeStateDoesNotLeakWhenWindowIdIsReused() {
        let workspace = focus.workspace
        let oldParent = TilingContainer(
            parent: workspace.rootTilingContainer,
            adaptiveWeight: 1,
            .h,
            .tiles,
            index: INDEX_BIND_LAST,
        )
        let oldWindow = TestWindow.new(id: 805, parent: oldParent)
        let driver = WindowMouseInteractionDriver.shared
        driver.toggleFloatingForShake(oldWindow)
        oldWindow.shakeWindowState.lastToggleTimestamp = 100

        let replacement = TestWindow.new(id: 805, parent: workspace)
        XCTAssertEqual(replacement.shakeWindowState.lastToggleTimestamp, -TimeInterval.infinity)
        XCTAssertNil(replacement.shakeWindowState.tilingPlacement)
        driver.toggleFloatingForShake(replacement)

        XCTAssertTrue(replacement.parent === workspace.rootTilingContainer)
        XCTAssertFalse(replacement.parent === oldParent)
    }

    func testDriverRecognizesOncePerGrabClearsPendingIntentAndHonorsCooldown() {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 806, parent: workspace.rootTilingContainer)
        let driver = WindowMouseInteractionDriver.shared
        let session = WindowMouseInteractionDriver.MoveSession(
            windowId: window.windowId,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: false,
        )
        setCurrentMouseManipulationKind(.move)
        pendingWindowDragIntent = testPendingShakeDragIntent(windowId: window.windowId)

        beginShakeRecognition(driver: driver, window: window, session: session, startingAt: 10)

        XCTAssertTrue(window.isFloating)
        XCTAssertTrue(driver.didToggleLayoutWithShake)
        XCTAssertNil(debugPendingWindowDragIntentSummary())

        driver.shakeGesture = WindowShakeGestureRecognizer()
        feedShake(driver: driver, window: window, session: session, startingAt: 12)
        XCTAssertTrue(window.isFloating, "A grab can toggle only once")

        driver.stop()
        beginShakeRecognition(driver: driver, window: window, session: session, startingAt: 10.6)
        XCTAssertTrue(window.isFloating, "The per-window cooldown survives driver reset")

        driver.stop()
        beginShakeRecognition(driver: driver, window: window, session: session, startingAt: 12)
        XCTAssertFalse(window.isFloating)
    }

    func testDisabledShakeConfigAndFloatingMoveSessionLifecycle() {
        let workspace = focus.workspace
        let tiled = TestWindow.new(id: 807, parent: workspace.rootTilingContainer)
        let driver = WindowMouseInteractionDriver.shared
        let session = WindowMouseInteractionDriver.MoveSession(
            windowId: tiled.windowId,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: false,
        )
        config.enableShakeToToggleTiling = false
        setCurrentMouseManipulationKind(.move)

        beginShakeRecognition(driver: driver, window: tiled, session: session, startingAt: 20)

        XCTAssertFalse(tiled.isFloating)
        XCTAssertFalse(driver.didToggleLayoutWithShake)

        driver.stop()
        let floating = TestWindow.new(id: 808, parent: workspace)
        moveFloatingWindowWithMouse(floating)
        XCTAssertEqual(driver.moveSession?.windowId, floating.windowId)
        XCTAssertEqual(getCurrentMouseManipulationKind(), .move)
        XCTAssertEqual(currentlyManipulatedWithMouseWindowId, floating.windowId)
    }

    private func beginShakeRecognition(
        driver: WindowMouseInteractionDriver,
        window: Window,
        session: WindowMouseInteractionDriver.MoveSession,
        startingAt: TimeInterval,
    ) {
        driver.shakeGesture = WindowShakeGestureRecognizer()
        driver.didToggleLayoutWithShake = false
        feedShake(driver: driver, window: window, session: session, startingAt: startingAt)
    }

    private func feedShake(
        driver: WindowMouseInteractionDriver,
        window: Window,
        session: WindowMouseInteractionDriver.MoveSession,
        startingAt: TimeInterval,
    ) {
        for (index, x) in [0, 65, 0, 65, 0].enumerated() {
            MousePointerTracker.shared.note(
                point: CGPoint(x: CGFloat(x) - 10_000, y: -10_000),
                timestamp: startingAt + Double(index) * 0.12,
            )
            driver.detectShakeIfNeeded(sourceWindow: window, session: session)
        }
    }

    private func testPendingShakeDragIntent(windowId: UInt32) -> PendingWindowDragIntent {
        PendingWindowDragIntent(
            sourceWindowId: windowId,
            sourceSubject: .window,
            kind: .moveToWorkspace(workspaceName: "elsewhere"),
            previewRect: Rect(topLeftX: 0, topLeftY: 0, width: 10, height: 10),
            interactionRect: Rect(topLeftX: 0, topLeftY: 0, width: 10, height: 10),
            title: "Move",
            subtitle: "Move",
            previewStyle: .workspaceMove,
            previewGeometry: .rounded,
            isGroup: false,
            isPointerSettled: true,
        )
    }
}
