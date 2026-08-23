@testable import AppBundle
import XCTest

/// normalizeLayoutReason runs on every refresh barrier. The native fullscreen/minimized state it
/// needs is cached per window and invalidated by AX events (moved/resized/miniaturized/
/// deminiaturized), so a steady-state barrier must not re-poll every window over AX.
final class NormalizeLayoutReasonCacheTest: XCTestCase {
    @MainActor
    func testSteadyStateBarrierDoesNotRefetchNativeState() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "normalize-cache-test")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        try await normalizeLayoutReason()
        let fetchesAfterFirstPass = window.nativeStateFetchCount
        XCTAssertGreaterThan(fetchesAfterFirstPass, 0, "first pass must observe the window's native state")

        try await normalizeLayoutReason()
        try await normalizeLayoutReason()
        XCTAssertEqual(
            window.nativeStateFetchCount, fetchesAfterFirstPass,
            "steady-state passes must be answered by the event-invalidated cache"
        )
    }

    @MainActor
    func testNativeStateChangeIsObservedAfterInvalidation() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "normalize-cache-test")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        try await normalizeLayoutReason()
        XCTAssertTrue(window.parent is TilingContainer)

        // Mutating the fake native state invalidates the cache (modeling the AX event that
        // accompanies every real transition), so the next pass must re-observe and react.
        window.nativeIsMacosFullscreen = true
        try await normalizeLayoutReason()
        XCTAssertTrue(
            window.parent is MacosFullscreenWindowsContainer,
            "fullscreen transition must be observed on the pass after invalidation"
        )

        window.nativeIsMacosFullscreen = false
        try await normalizeLayoutReason()
        XCTAssertTrue(
            window.parent is TilingContainer,
            "exiting fullscreen must restore the window to its tiling container"
        )
    }

    @MainActor
    func testMinimizedTransitionIsObservedAfterInvalidation() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "normalize-cache-test")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        try await normalizeLayoutReason()
        window.nativeIsMacosMinimized = true
        try await normalizeLayoutReason()
        XCTAssertTrue(window.parent is MacosMinimizedWindowsContainer)

        window.nativeIsMacosMinimized = false
        try await normalizeLayoutReason()
        XCTAssertTrue(window.parent is TilingContainer)
    }

    /// An async AX observation races the events that invalidate the caches: a value fetched
    /// before a transition must not be written back after the transition's invalidation ran,
    /// because nothing would ever invalidate the resurrected stale value again.
    @MainActor
    func testStaleObservationWriteBackIsDiscarded() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "normalize-cache-test")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        // Observation started (token captured), then the window transitioned (invalidation).
        let staleToken = window.nativeStateObservationToken()
        window.nativeIsMacosFullscreen = true // didSet models the transition's AX event
        window.recordObservedNativeState(fullscreen: false, minimized: false, token: staleToken)
        XCTAssertNil(window.lastKnownNativeFullscreen, "stale observation must be discarded")

        // A fresh observation (token captured after the invalidation) is recorded.
        let freshToken = window.nativeStateObservationToken()
        window.recordObservedNativeState(fullscreen: true, minimized: false, token: freshToken)
        XCTAssertEqual(window.lastKnownNativeFullscreen, true)

        // Same guard for the rect cache.
        let staleRectToken = window.nativeStateObservationToken()
        window.invalidateLastKnownNativeState()
        window.recordObservedActualRect(Rect(topLeftX: 1, topLeftY: 2, width: 3, height: 4), token: staleRectToken)
        XCTAssertNil(window.lastKnownActualRect, "stale rect observation must be discarded")

        // An authoritative write supersedes an in-flight observation.
        let preAuthoritativeToken = window.nativeStateObservationToken()
        let authoritative = Rect(topLeftX: 10, topLeftY: 20, width: 30, height: 40)
        window.recordAuthoritativeActualRect(authoritative)
        window.recordObservedActualRect(Rect(topLeftX: 5, topLeftY: 6, width: 7, height: 8), token: preAuthoritativeToken)
        XCTAssertEqual(window.lastKnownActualRect, authoritative, "authoritative write must win over an older in-flight observation")
    }
}
