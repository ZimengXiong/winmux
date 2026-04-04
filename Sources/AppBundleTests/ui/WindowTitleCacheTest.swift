@testable import AppBundle
import XCTest

final class WindowTitleCacheTest: XCTestCase {
    @MainActor
    func testGetCachedWindowTitleReusesFreshValue() async {
        resetCachedWindowTitles()
        let window = StubTitleWindow(id: 42, title: "  Example  ")

        let first = await getCachedWindowTitle(window, maxAge: 60, now: Date(timeIntervalSince1970: 10))
        let second = await getCachedWindowTitle(window, maxAge: 60, now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(first, "Example")
        XCTAssertEqual(second, "Example")
        XCTAssertEqual(window.titleGetCount, 1)
    }

    @MainActor
    func testGetCachedWindowTitleRefreshesExpiredValue() async {
        resetCachedWindowTitles()
        let window = StubTitleWindow(id: 43, title: "First")

        let first = await getCachedWindowTitle(window, maxAge: 1, now: Date(timeIntervalSince1970: 10))
        window.stubTitle = "Second"
        let second = await getCachedWindowTitle(window, maxAge: 1, now: Date(timeIntervalSince1970: 12))

        XCTAssertEqual(first, "First")
        XCTAssertEqual(second, "Second")
        XCTAssertEqual(window.titleGetCount, 2)
    }
}

private final class StubTitleWindow: Window {
    var stubTitle: String
    var titleGetCount: Int = 0

    @MainActor
    init(id: UInt32, title: String) {
        stubTitle = title
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: Workspace.get(byName: "cache-test"), adaptiveWeight: 1, index: INDEX_BIND_LAST)
    }

    override func closeAxWindow() {}

    @MainActor
    override var title: String {
        get async {
            titleGetCount += 1
            return stubTitle
        }
    }

    @MainActor override var isMacosFullscreen: Bool { get async throws { false } }
    @MainActor override var isMacosMinimized: Bool { get async throws { false } }
}
