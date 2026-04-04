@testable import AppBundle
import AppKit
import XCTest

final class AxRefreshFastPathTest: XCTestCase {
    @MainActor
    func testFocusedWindowChangedSkipsFullRefreshBarrier() async throws {
        let (first, second) = setUpFocusScenario()
        var refreshCount = 0
        var normalizeCount = 0
        setBlockingRefreshOverridesForTests(
            refresh: { refreshCount += 1 },
            normalizeLayoutReason: { normalizeCount += 1 }
        )

        _ = first.focusWindow()
        TestApp.shared.focusedWindow = second

        try await runRefreshSessionBlocking(.ax(kAXFocusedWindowChangedNotification as String))

        XCTAssertEqual(focus.windowOrNil?.windowId, second.windowId)
        XCTAssertEqual(refreshCount, 0)
        XCTAssertEqual(normalizeCount, 0)
    }

    @MainActor
    func testAppActivationSkipsFullRefreshBarrier() async throws {
        let (first, second) = setUpFocusScenario()
        var refreshCount = 0
        var normalizeCount = 0
        setBlockingRefreshOverridesForTests(
            refresh: { refreshCount += 1 },
            normalizeLayoutReason: { normalizeCount += 1 }
        )

        _ = first.focusWindow()
        TestApp.shared.focusedWindow = second

        try await runRefreshSessionBlocking(.globalObserver(NSWorkspace.didActivateApplicationNotification.rawValue))

        XCTAssertEqual(focus.windowOrNil?.windowId, second.windowId)
        XCTAssertEqual(refreshCount, 0)
        XCTAssertEqual(normalizeCount, 0)
    }

    @MainActor
    func testWindowCreatedStillRunsFullRefreshBarrier() async throws {
        _ = setUpFocusScenario()
        var refreshCount = 0
        var normalizeCount = 0
        setBlockingRefreshOverridesForTests(
            refresh: { refreshCount += 1 },
            normalizeLayoutReason: { normalizeCount += 1 }
        )

        try await runRefreshSessionBlocking(.ax(kAXWindowCreatedNotification as String))

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(normalizeCount, 1)
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
        return (first, second)
    }
}
