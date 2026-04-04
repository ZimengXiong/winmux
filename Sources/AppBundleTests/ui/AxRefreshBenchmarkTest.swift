@testable import AppBundle
import AppKit
import Common
import XCTest

final class AxRefreshBenchmarkTest: XCTestCase {
    @MainActor
    func testBenchmark() async throws {
        try await runScenario(
            name: "focused-window-changed",
            event: .ax(kAXFocusedWindowChangedNotification as String),
            expectedRefreshCount: 0,
            expectedNormalizeCount: 0
        )
        try await runScenario(
            name: "window-created",
            event: .ax(kAXWindowCreatedNotification as String),
            expectedRefreshCount: 10,
            expectedNormalizeCount: 10
        )
        try await runScenario(
            name: "app-activation",
            event: .globalObserver(NSWorkspace.didActivateApplicationNotification.rawValue),
            expectedRefreshCount: 0,
            expectedNormalizeCount: 0
        )
    }

    @MainActor
    private func runScenario(
        name: String,
        event: RefreshSessionEvent,
        expectedRefreshCount: Int,
        expectedNormalizeCount: Int,
    ) async throws {
        let (first, second) = setUpFocusScenario()
        var refreshCount = 0
        var normalizeCount = 0
        let refreshDelayNanoseconds: UInt64 = 80_000_000
        let normalizeDelayNanoseconds: UInt64 = 40_000_000
        setBlockingRefreshOverridesForTests(
            refresh: {
                refreshCount += 1
                try await Task.sleep(nanoseconds: refreshDelayNanoseconds)
            },
            normalizeLayoutReason: {
                normalizeCount += 1
                try await Task.sleep(nanoseconds: normalizeDelayNanoseconds)
            }
        )

        let iterations = 10
        let start = DispatchTime.now().uptimeNanoseconds
        for iteration in 0 ..< iterations {
            let target = iteration.isMultiple(of: 2) ? first : second
            TestApp.shared.focusedWindow = target
            try await runRefreshSessionBlocking(event)
        }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start

        let result = AxRefreshBenchmarkResult(
            branch: ProcessInfo.processInfo.environment["AX_REFRESH_BENCHMARK_LABEL"] ?? "unknown",
            scenario: name,
            event: event.description,
            iterations: iterations,
            refreshDelayMilliseconds: Double(refreshDelayNanoseconds) / 1_000_000,
            normalizeDelayMilliseconds: Double(normalizeDelayNanoseconds) / 1_000_000,
            refreshCount: refreshCount,
            normalizeCount: normalizeCount,
            elapsedMilliseconds: Double(elapsedNanoseconds) / 1_000_000,
        )
        print("AX_REFRESH_BENCHMARK \(result.json)")

        XCTAssertEqual(refreshCount, expectedRefreshCount)
        XCTAssertEqual(normalizeCount, expectedNormalizeCount)
    }

    @MainActor
    private func setUpFocusScenario() -> (TestWindow, TestWindow) {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true
        appForTests = TestApp.shared
        let workspace = focus.workspace
        let first = TestWindow.new(
            id: 1,
            parent: workspace.rootTilingContainer,
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 800, height: 600)
        )
        let second = TestWindow.new(
            id: 2,
            parent: workspace.rootTilingContainer,
            rect: Rect(topLeftX: 800, topLeftY: 0, width: 800, height: 600)
        )
        _ = first.focusWindow()
        TestApp.shared.focusedWindow = first
        return (first, second)
    }
}

private struct AxRefreshBenchmarkResult: Codable {
    let branch: String
    let scenario: String
    let event: String
    let iterations: Int
    let refreshDelayMilliseconds: Double
    let normalizeDelayMilliseconds: Double
    let refreshCount: Int
    let normalizeCount: Int
    let elapsedMilliseconds: Double

    var json: String {
        String(data: try! JSONEncoder().encode(self), encoding: .utf8)!
    }
}
