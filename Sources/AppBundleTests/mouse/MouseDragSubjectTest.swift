@testable import AppBundle
import CoreGraphics
import XCTest

final class MouseDragSubjectTest: XCTestCase {
    func testShouldPromoteWindowDragToTabGroupDrag() {
        XCTAssertTrue(shouldPromoteWindowDragToTabGroupDrag(isOptionPressed: true, isTabbedWindow: true))
        XCTAssertFalse(shouldPromoteWindowDragToTabGroupDrag(isOptionPressed: false, isTabbedWindow: true))
        XCTAssertFalse(shouldPromoteWindowDragToTabGroupDrag(isOptionPressed: true, isTabbedWindow: false))
    }

    func testSameWorkspaceSurfaceIntentRulesInUnmanagedMode() {
        XCTAssertTrue(shouldAllowSameWorkspaceWindowSurfaceIntent(
            enableWindowManagement: false,
            subject: .window,
            detachOrigin: .window,
            isOptionPressed: true,
        ))
        XCTAssertFalse(shouldAllowSameWorkspaceWindowSurfaceIntent(
            enableWindowManagement: false,
            subject: .window,
            detachOrigin: .window,
            isOptionPressed: false,
        ))
        XCTAssertTrue(shouldAllowSameWorkspaceWindowSurfaceIntent(
            enableWindowManagement: false,
            subject: .window,
            detachOrigin: .tabStrip,
            isOptionPressed: false,
        ))
        XCTAssertFalse(shouldAllowSameWorkspaceWindowSurfaceIntent(
            enableWindowManagement: false,
            subject: .group,
            detachOrigin: .window,
            isOptionPressed: true,
        ))
    }

    func testWindowDragFrameGateCoalescesFastSamples() {
        var gate = WindowDragFrameGateCore(minimumInterval: 0.01, settledVelocityThreshold: 100)

        XCTAssertTrue(gate.shouldProcess(point: CGPoint(x: 0, y: 0), timestamp: 10))
        XCTAssertFalse(gate.shouldProcess(point: CGPoint(x: 100, y: 0), timestamp: 10.005))

        XCTAssertEqual(gate.state?.point, CGPoint(x: 0, y: 0))
    }

    func testWindowDragFrameGateTracksVelocityAndSettledState() {
        var gate = WindowDragFrameGateCore(minimumInterval: 0.01, settledVelocityThreshold: 100)

        XCTAssertTrue(gate.shouldProcess(point: CGPoint(x: 0, y: 0), timestamp: 10))
        XCTAssertTrue(gate.shouldProcess(point: CGPoint(x: 30, y: 0), timestamp: 10.02))
        XCTAssertEqual(gate.state?.velocity ?? 0, 1_500, accuracy: 0.001)
        XCTAssertEqual(gate.state?.isSettled, false)

        XCTAssertTrue(gate.shouldProcess(point: CGPoint(x: 31, y: 0), timestamp: 10.04))
        XCTAssertEqual(gate.state?.velocity ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(gate.state?.isSettled, true)
    }

    func testWindowDragFrameGateForceProcessesSample() {
        var gate = WindowDragFrameGateCore(minimumInterval: 1, settledVelocityThreshold: 100)

        XCTAssertTrue(gate.shouldProcess(point: CGPoint(x: 0, y: 0), timestamp: 10))
        XCTAssertTrue(gate.shouldProcess(point: CGPoint(x: 10, y: 0), timestamp: 10.1, force: true))

        XCTAssertEqual(gate.state?.point, CGPoint(x: 10, y: 0))
    }

    func testResizeGestureCandidateEdgesStayTightToActualFrameEdges() {
        let rect = Rect(topLeftX: 100, topLeftY: 100, width: 500, height: 300)

        XCTAssertEqual(
            resizeGestureCandidateEdges(mouse: CGPoint(x: 592, y: 164), rect: rect),
            ResizeGestureEdges(left: false, right: true, up: false, down: false)
        )
    }

    func testResizeGestureCalibrationCorrectsPendingCornerGuessFromObservedDelta() {
        let baseRect = Rect(topLeftX: 0, topLeftY: 0, width: 400, height: 300)
        var gesture = makeResizeGestureSession(
            windowId: 1,
            baseRect: baseRect,
            observedRect: baseRect,
            mouse: CGPoint(x: 400, y: 20),
            edges: ResizeGestureEdges(left: false, right: true, up: true, down: false),
            timestamp: 10,
        ).orDie()

        gesture.calibrate(
            observedRect: Rect(topLeftX: 0, topLeftY: 0, width: 450, height: 300),
            mouse: CGPoint(x: 450, y: 20),
            timestamp: 10.1,
        )

        XCTAssertEqual(gesture.edges, ResizeGestureEdges(left: false, right: true, up: false, down: false))
        let predicted = gesture.predictedRect(mouse: CGPoint(x: 460, y: 60))
        XCTAssertEqual(predicted.width, 460)
        XCTAssertEqual(predicted.height, 300)
    }

    func testMouseInteractionHiddenIdsStayHiddenUntilSessionRestore() {
        XCTAssertEqual(
            nextMouseInteractionHiddenWindowIds(activeWindowId: 1, currentlyHidden: [2, 3], discovered: []),
            [2, 3]
        )
        XCTAssertEqual(
            nextMouseInteractionHiddenWindowIds(activeWindowId: 2, currentlyHidden: [2, 3], discovered: [4]),
            [3, 4]
        )
    }
}
