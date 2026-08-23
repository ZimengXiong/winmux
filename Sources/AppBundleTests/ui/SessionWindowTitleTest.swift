@testable import AppBundle
import XCTest

/// getSessionWindowTitle is the title accessor for per-session UI model builders: a known
/// window answers from the cache immediately (even past TTL — the stale entry is refreshed in
/// the background), while a first-sight window is fetched inline so its first paint is correct.
final class SessionWindowTitleTest: XCTestCase {
    @MainActor
    func testFirstSightFetchesInline() async {
        setUpWorkspacesForTests()
        resetCachedWindowTitles()
        let window = StubSessionTitleWindow(id: 61, title: "Inline")

        let title = await getSessionWindowTitle(window)

        XCTAssertEqual(title, "Inline")
        XCTAssertEqual(window.titleGetCount, 1)
    }

    @MainActor
    func testStaleEntryAnswersImmediatelyWithoutInlineFetch() async {
        setUpWorkspacesForTests()
        resetCachedWindowTitles()
        let window = StubSessionTitleWindow(id: 62, title: "Old")
        _ = await getCachedWindowTitle(window, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(window.titleGetCount, 1)

        window.stubTitle = "New"
        // Way past the 5s TTL: the session accessor must return the stale value synchronously
        // rather than blocking the session on an AX round-trip.
        let title = await getSessionWindowTitle(window, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(title, "Old")
        XCTAssertEqual(window.titleGetCount, 1, "stale entry must not be refreshed inline")

        // The queued background refresh eventually updates the cache.
        for _ in 0 ..< 1000 {
            if cachedWindowTitle(for: window) == "New" { break }
            await Task.yield()
        }
        XCTAssertEqual(cachedWindowTitle(for: window), "New")
        XCTAssertEqual(window.titleGetCount, 2)
    }

    @MainActor
    func testFreshEntryDoesNotScheduleBackgroundRefresh() async {
        setUpWorkspacesForTests()
        resetCachedWindowTitles()
        let window = StubSessionTitleWindow(id: 63, title: "Fresh")
        let now = Date()
        _ = await getCachedWindowTitle(window, now: now)

        let title = await getSessionWindowTitle(window, now: now.addingTimeInterval(1))
        XCTAssertEqual(title, "Fresh")

        for _ in 0 ..< 50 { await Task.yield() }
        XCTAssertEqual(window.titleGetCount, 1, "fresh entries must not be re-fetched")
    }
}

private final class StubSessionTitleWindow: Window {
    var stubTitle: String
    var titleGetCount: Int = 0

    @MainActor
    init(id: UInt32, title: String) {
        stubTitle = title
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: Workspace.get(byName: "session-title-test"), adaptiveWeight: 1, index: INDEX_BIND_LAST)
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
