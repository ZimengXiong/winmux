@testable import AppBundle
import XCTest

final class WindowTitleBenchmarkTest: XCTestCase {
    @MainActor
    func testWindowTitleRefreshBenchmark() async throws {
        try await runScenario(name: "cold", iterations: 1)
        try await runScenario(name: "steady", iterations: 10)
    }

    @MainActor
    private func runScenario(name: String, iterations: Int) async throws {
        setUpWorkspacesForTests()

        TrayMenuModel.shared.isEnabled = true
        TrayMenuModel.shared.workspaceSidebarWorkspaces = []
        TrayMenuModel.shared.windowTabStrips = []
        TrayMenuModel.shared.workspaceSidebarVisibleWidth = 0
        TrayMenuModel.shared.workspaceSidebarTopPadding = 12
        TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = nil
        TrayMenuModel.shared.isWorkspaceSidebarExpanded = false

        config.workspaceSidebar.enabled = true
        config.windowTabs.enabled = true

        let workspaceCount = 4
        let windowsPerWorkspace = 5
        let titleDelayNanoseconds: UInt64 = 1_000_000

        for workspaceIndex in 0 ..< workspaceCount {
            let workspace = Workspace.get(byName: "bench-\(workspaceIndex)")
            workspace.rootTilingContainer.layout = .accordion
            for windowIndex in 0 ..< windowsPerWorkspace {
                _ = BenchmarkTitleWindow.new(
                    id: UInt32(workspaceIndex * 100 + windowIndex + 1),
                    parent: workspace.rootTilingContainer,
                    title: "Window \(workspaceIndex)-\(windowIndex)",
                )
            }
        }

        let visibleWorkspace = Workspace.get(byName: "bench-0")
        XCTAssertTrue(visibleWorkspace.focusWorkspace())
        try await visibleWorkspace.layoutWorkspace()

        BenchmarkTitleWindow.reset(delayNanoseconds: titleDelayNanoseconds)

        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< iterations {
            await updateWorkspaceSidebarModel()
            await updateWindowTabModel()
        }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start

        let result = WindowTitleBenchmarkResult(
            branch: ProcessInfo.processInfo.environment["WINDOW_TITLE_BENCHMARK_LABEL"] ?? "unknown",
            scenario: name,
            iterations: iterations,
            workspaceCount: workspaceCount,
            windowsPerWorkspace: windowsPerWorkspace,
            titleDelayMilliseconds: Double(titleDelayNanoseconds) / 1_000_000,
            titleGetCount: BenchmarkTitleWindow.titleGetCount,
            elapsedMilliseconds: Double(elapsedNanoseconds) / 1_000_000,
        )
        print("WINDOW_TITLE_BENCHMARK \(result.json)")

        XCTAssertGreaterThan(BenchmarkTitleWindow.titleGetCount, 0)
    }
}

private struct WindowTitleBenchmarkResult: Codable {
    let branch: String
    let scenario: String
    let iterations: Int
    let workspaceCount: Int
    let windowsPerWorkspace: Int
    let titleDelayMilliseconds: Double
    let titleGetCount: Int
    let elapsedMilliseconds: Double

    var json: String {
        String(data: try! JSONEncoder().encode(self), encoding: .utf8)!
    }
}

private final class BenchmarkTitleWindow: Window {
    @MainActor static var titleGetCount: Int = 0
    @MainActor private static var titleDelayNanoseconds: UInt64 = 0

    private var rect: Rect?
    private let backingTitle: String

    @MainActor
    private init(id: UInt32, parent: NonLeafTreeNodeObject, title: String) {
        backingTitle = title
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: parent, adaptiveWeight: 1, index: INDEX_BIND_LAST)
    }

    @MainActor
    static func new(id: UInt32, parent: NonLeafTreeNodeObject, title: String) -> BenchmarkTitleWindow {
        let window = BenchmarkTitleWindow(id: id, parent: parent, title: title)
        TestApp.shared._windows.append(window)
        return window
    }

    @MainActor
    static func reset(delayNanoseconds: UInt64) {
        titleGetCount = 0
        titleDelayNanoseconds = delayNanoseconds
    }

    override func closeAxWindow() {
        unbindFromParent()
    }

    @MainActor
    override var title: String {
        get async {
            Self.titleGetCount += 1
            if Self.titleDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: Self.titleDelayNanoseconds)
            }
            return backingTitle
        }
    }

    @MainActor
    override func nativeFocus() {
        appForTests = TestApp.shared
        TestApp.shared.focusedWindow = self
    }

    @MainActor override func getAxRect() async throws -> Rect? { rect }
    @MainActor override var isMacosFullscreen: Bool { get async throws { false } }
    @MainActor override var isMacosMinimized: Bool { get async throws { false } }
    override var isHiddenInCorner: Bool { false }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        let currentRect = rect ?? Rect(topLeftX: topLeft?.x ?? 0, topLeftY: topLeft?.y ?? 0, width: size?.width ?? 0, height: size?.height ?? 0)
        rect = Rect(
            topLeftX: topLeft?.x ?? currentRect.topLeftX,
            topLeftY: topLeft?.y ?? currentRect.topLeftY,
            width: size?.width ?? currentRect.width,
            height: size?.height ?? currentRect.height,
        )
    }
}
