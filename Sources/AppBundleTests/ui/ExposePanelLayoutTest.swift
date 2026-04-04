import AppKit
@testable import AppBundle
import XCTest

final class ExposePanelLayoutTest: XCTestCase {
    func testExpandedGroupLayoutUsesWideViewportForManyPortraitTabs() {
        let viewport = CGSize(width: 760, height: 1040)
        let layout = bestExposeExpandedGroupLayout(
            itemCount: 8,
            aspectRatio: 0.32,
            viewportSize: viewport,
            minimumMainCardHeight: 280,
        )

        XCTAssertGreaterThanOrEqual(layout.columns, 5)
        XCTAssertGreaterThan(layout.mainCardHeight, 280)
        XCTAssertGreaterThan(layout.totalSize.width, 500)
        XCTAssertLessThanOrEqual(layout.totalSize.width, viewport.width - 96)
        XCTAssertLessThanOrEqual(layout.totalSize.height, viewport.height - 96)
    }

    func testExpandedGroupLayoutKeepsSingleWindowWithinViewport() {
        let viewport = CGSize(width: 900, height: 700)
        let layout = bestExposeExpandedGroupLayout(
            itemCount: 1,
            aspectRatio: 1.4,
            viewportSize: viewport,
            minimumMainCardHeight: 260,
        )

        XCTAssertEqual(layout.columns, 1)
        XCTAssertEqual(layout.rowCount, 0)
        XCTAssertGreaterThanOrEqual(layout.mainCardHeight, 260)
        XCTAssertLessThanOrEqual(layout.totalSize.width, viewport.width - 96)
        XCTAssertLessThanOrEqual(layout.totalSize.height, viewport.height - 96)
    }
}
