@testable import AppBundle
import XCTest

final class SwitcherPaletteTest: XCTestCase {
    private func item(_ id: UInt32, app: String, title: String, workspace: String = "1") -> SwitcherPaletteItem {
        SwitcherPaletteItem(id: id, title: title, appName: app, icon: nil, workspaceName: workspace, isFocused: false)
    }

    func testEmptyQueryKeepsOriginalOrder() {
        let items = [item(1, app: "Safari", title: "Docs"), item(2, app: "Ghostty", title: "zsh")]
        XCTAssertEqual(filterSwitcherPaletteItems(items, query: "  ").map(\.id), [1, 2])
    }

    func testNonMatchingItemsAreDropped() {
        let items = [item(1, app: "Safari", title: "Docs"), item(2, app: "Ghostty", title: "zsh")]
        XCTAssertEqual(filterSwitcherPaletteItems(items, query: "ghos").map(\.id), [2])
    }

    func testWordStartAndConsecutiveMatchesRankAboveScattered() {
        let items = [
            item(1, app: "Calendar", title: "June"), // scattered "cal" not at word start? it is prefix
            item(2, app: "Books", title: "local archive"), // "cal" inside "local"
        ]
        XCTAssertEqual(filterSwitcherPaletteItems(items, query: "cal").first?.id, 1)
    }

    func testSubsequenceMatchesAcrossFields() {
        let items = [item(7, app: "Zed", title: "refresh.swift", workspace: "code")]
        XCTAssertEqual(filterSwitcherPaletteItems(items, query: "zed refresh").map(\.id), [7])
        XCTAssertEqual(filterSwitcherPaletteItems(items, query: "xyzzy").map(\.id), [])
    }

    func testFuzzyScoreRejectsNonSubsequence() {
        XCTAssertNil(switcherPaletteFuzzyScore("ba", in: "ab"))
        XCTAssertNotNil(switcherPaletteFuzzyScore("ab", in: "a-b"))
    }
}
