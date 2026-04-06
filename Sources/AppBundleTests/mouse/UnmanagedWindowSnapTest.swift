@testable import AppBundle
import XCTest

final class UnmanagedWindowSnapTest: XCTestCase {
    func testTopEdgeMaximizes() {
        let workspaceRect = Rect(topLeftX: 0, topLeftY: 0, width: 900, height: 600)

        XCTAssertEqual(
            unmanagedSnapAction(
                at: CGPoint(x: 450, y: 1),
                in: workspaceRect,
                priorAction: nil,
            ),
            .maximize,
        )
    }

    func testBottomCenterPromotesThirdsToTwoThirds() {
        let workspaceRect = Rect(topLeftX: 0, topLeftY: 0, width: 900, height: 600)

        XCTAssertEqual(
            unmanagedSnapAction(
                at: CGPoint(x: 450, y: 598),
                in: workspaceRect,
                priorAction: .firstThird,
            ),
            .firstTwoThirds,
        )
        XCTAssertEqual(
            unmanagedSnapAction(
                at: CGPoint(x: 450, y: 598),
                in: workspaceRect,
                priorAction: .lastThird,
            ),
            .lastTwoThirds,
        )
        XCTAssertEqual(
            unmanagedSnapAction(
                at: CGPoint(x: 450, y: 598),
                in: workspaceRect,
                priorAction: nil,
            ),
            .centerThird,
        )
    }

    func testLeftEdgeShortZonesBecomeTopAndBottomHalves() {
        let workspaceRect = Rect(topLeftX: 0, topLeftY: 0, width: 900, height: 600)

        XCTAssertEqual(
            unmanagedSnapAction(
                at: CGPoint(x: 1, y: 80),
                in: workspaceRect,
                priorAction: nil,
            ),
            .topHalf,
        )
        XCTAssertEqual(
            unmanagedSnapAction(
                at: CGPoint(x: 1, y: 500),
                in: workspaceRect,
                priorAction: nil,
            ),
            .bottomHalf,
        )
    }

    func testPortraitBottomEdgeSplitsIntoLeftAndRightHalves() {
        let portraitRect = Rect(topLeftX: 0, topLeftY: 0, width: 600, height: 900)

        XCTAssertEqual(
            unmanagedSnapAction(
                at: CGPoint(x: 120, y: 898),
                in: portraitRect,
                priorAction: nil,
            ),
            .leftHalf,
        )
        XCTAssertEqual(
            unmanagedSnapAction(
                at: CGPoint(x: 480, y: 898),
                in: portraitRect,
                priorAction: nil,
            ),
            .rightHalf,
        )
    }
}
