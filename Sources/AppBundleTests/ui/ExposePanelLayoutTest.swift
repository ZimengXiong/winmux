import AppKit
@testable import AppBundle
import XCTest

final class ExposePanelLayoutTest: XCTestCase {
    func testOrderedExposeItemsMovesFocusedWindowToFrontAndPreservesRemainingOrder() {
        let items = [
            exposeTestItem(id: 11, focused: false),
            exposeTestItem(id: 22, focused: false),
            exposeTestItem(id: 33, focused: true),
            exposeTestItem(id: 44, focused: false),
        ]

        XCTAssertEqual(
            orderedExposeItemsForExpandedGroup(items).map(\.id),
            [33, 11, 22, 44],
        )
    }

    func testOrderedExposeItemsLeavesOrderUntouchedWhenNothingIsFocused() {
        let items = [
            exposeTestItem(id: 11, focused: false),
            exposeTestItem(id: 22, focused: false),
            exposeTestItem(id: 33, focused: false),
        ]

        XCTAssertEqual(
            orderedExposeItemsForExpandedGroup(items).map(\.id),
            [11, 22, 33],
        )
    }

    func testExpandedGroupHoverRectUnionsFramesForMatchingGroupAndAddsPadding() {
        let frames = [
            ExposeExpandedGroupFrame(groupId: "a", frame: CGRect(x: 100, y: 200, width: 80, height: 60)),
            ExposeExpandedGroupFrame(groupId: "a", frame: CGRect(x: 210, y: 190, width: 70, height: 90)),
            ExposeExpandedGroupFrame(groupId: "b", frame: CGRect(x: 20, y: 30, width: 40, height: 50)),
        ]

        XCTAssertEqual(
            exposeExpandedGroupHoverRect(groupId: "a", within: frames, padding: 10),
            CGRect(x: 90, y: 180, width: 200, height: 110),
        )
    }

    func testShouldKeepExpandedGroupVisibleAcceptsOriginalCollapsedFrame() {
        XCTAssertTrue(
            shouldKeepExpandedGroupVisible(
                location: CGPoint(x: 108, y: 108),
                groupId: "a",
                expandedFrames: [],
                collapsedOriginFrame: CGRect(x: 100, y: 100, width: 20, height: 20),
                padding: 10,
            ),
        )
    }

    func testShouldKeepExpandedGroupVisibleAcceptsExpandedFramesUnion() {
        let frames = [
            ExposeExpandedGroupFrame(groupId: "a", frame: CGRect(x: 200, y: 200, width: 40, height: 40)),
            ExposeExpandedGroupFrame(groupId: "a", frame: CGRect(x: 260, y: 200, width: 40, height: 40)),
        ]

        XCTAssertTrue(
            shouldKeepExpandedGroupVisible(
                location: CGPoint(x: 250, y: 220),
                groupId: "a",
                expandedFrames: frames,
                collapsedOriginFrame: nil,
                padding: 10,
            ),
        )
        XCTAssertFalse(
            shouldKeepExpandedGroupVisible(
                location: CGPoint(x: 120, y: 120),
                groupId: "a",
                expandedFrames: frames,
                collapsedOriginFrame: nil,
                padding: 10,
            ),
        )
    }

    func testHoveredCollapsedGroupFrameUsesPadding() {
        let frames = [
            ExposeCollapsedGroupFrame(groupId: "a", frame: CGRect(x: 100, y: 100, width: 40, height: 40)),
            ExposeCollapsedGroupFrame(groupId: "b", frame: CGRect(x: 200, y: 100, width: 40, height: 40)),
        ]

        XCTAssertEqual(
            hoveredCollapsedGroupFrame(
                at: CGPoint(x: 96, y: 120),
                within: frames,
                padding: 6,
            )?.groupId,
            "a",
        )
    }

}

private func exposeTestItem(id: UInt32, focused: Bool) -> ExposeWindowItem {
    ExposeWindowItem(
        id: id,
        title: "w\(id)",
        appName: "Test",
        thumbnail: nil,
        aspectRatio: 1.4,
        isFocused: focused,
        widthRatio: 1.0,
    )
}
