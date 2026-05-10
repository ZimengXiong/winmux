import Common
import XCTest

final class StringExTest: XCTestCase {
    func testJoinTruncatingCountsFirstElementBeforeAppendingNextElement() {
        XCTAssertEqual(
            ["Safari", "Calendar"].joinTruncating(separator: ", ", length: 8),
            "Safari, …",
        )
    }

    func testJoinTruncatingTruncatesFirstElementWhenItExceedsLimit() {
        XCTAssertEqual(
            ["VeryLongName"].joinTruncating(separator: ", ", length: 4),
            "Very…",
        )
    }
}
