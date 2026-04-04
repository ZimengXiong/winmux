import AppKit
@testable import AppBundle
import XCTest

final class ExposePanelHoverTest: XCTestCase {
    func testHoveredExposeItemIdReturnsMatchingCard() {
        let frames = [
            ExposeHoverTargetFrame(itemId: 11, frame: CGRect(x: 0, y: 0, width: 100, height: 80)),
            ExposeHoverTargetFrame(itemId: 22, frame: CGRect(x: 120, y: 0, width: 100, height: 80)),
        ]

        XCTAssertEqual(
            hoveredExposeItemId(at: CGPoint(x: 150, y: 40), within: frames),
            22,
        )
    }

    func testHoveredExposeItemIdReturnsNilOutsideAllCards() {
        let frames = [
            ExposeHoverTargetFrame(itemId: 11, frame: CGRect(x: 0, y: 0, width: 100, height: 80)),
            ExposeHoverTargetFrame(itemId: 22, frame: CGRect(x: 120, y: 0, width: 100, height: 80)),
        ]

        XCTAssertNil(hoveredExposeItemId(at: CGPoint(x: 110, y: 40), within: frames))
    }

    func testHoveredExposeItemIdPrefersLastMatchingFrame() {
        let frames = [
            ExposeHoverTargetFrame(itemId: 11, frame: CGRect(x: 0, y: 0, width: 120, height: 120)),
            ExposeHoverTargetFrame(itemId: 22, frame: CGRect(x: 40, y: 40, width: 120, height: 120)),
        ]

        XCTAssertEqual(
            hoveredExposeItemId(at: CGPoint(x: 80, y: 80), within: frames),
            22,
        )
    }
}
