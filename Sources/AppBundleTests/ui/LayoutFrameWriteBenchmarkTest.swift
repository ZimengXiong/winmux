@testable import AppBundle
import Common
import XCTest

final class LayoutFrameWriteBenchmarkTest: XCTestCase {
    @MainActor
    func testRepeatedLayoutBenchmark() async throws {
        try await runScenario(name: "steady-hotkey", event: .hotkeyBinding, iterations: 10)
        try await runScenario(name: "steady-ax", event: .ax("benchmark"), iterations: 10)
    }

    @MainActor
    private func runScenario(name: String, event: RefreshSessionEvent, iterations: Int) async throws {
        setUpWorkspacesForTests()

        let workspace = Workspace.get(byName: "layout-bench")
        workspace.rootTilingContainer.layout = .tiles
        let windowCount = 6
        let frameDelayNanoseconds: UInt64 = 1_000_000
        for index in 0 ..< windowCount {
            _ = BenchmarkFrameWindow.new(
                id: UInt32(index + 1),
                parent: workspace.rootTilingContainer,
            )
        }
        XCTAssertTrue(workspace.focusWorkspace())

        BenchmarkFrameWindow.reset(delayNanoseconds: frameDelayNanoseconds)

        let start = DispatchTime.now().uptimeNanoseconds
        try await $refreshSessionEvent.withValue(event) {
            for _ in 0 ..< iterations {
                try await workspace.layoutWorkspace()
            }
        }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start

        let result = LayoutFrameWriteBenchmarkResult(
            branch: ProcessInfo.processInfo.environment["LAYOUT_FRAME_BENCHMARK_LABEL"] ?? "unknown",
            scenario: name,
            iterations: iterations,
            windowCount: windowCount,
            frameDelayMilliseconds: Double(frameDelayNanoseconds) / 1_000_000,
            frameWriteCount: BenchmarkFrameWindow.frameWriteCount,
            elapsedMilliseconds: Double(elapsedNanoseconds) / 1_000_000,
        )
        print("LAYOUT_FRAME_BENCHMARK \(result.json)")

        XCTAssertGreaterThan(BenchmarkFrameWindow.frameWriteCount, 0)
    }
}

private struct LayoutFrameWriteBenchmarkResult: Codable {
    let branch: String
    let scenario: String
    let iterations: Int
    let windowCount: Int
    let frameDelayMilliseconds: Double
    let frameWriteCount: Int
    let elapsedMilliseconds: Double

    var json: String {
        String(data: try! JSONEncoder().encode(self), encoding: .utf8)!
    }
}

private final class BenchmarkFrameWindow: Window {
    nonisolated(unsafe) static var frameWriteCount: Int = 0
    nonisolated(unsafe) private static var frameDelayNanoseconds: UInt64 = 0

    private var rect: Rect?

    @MainActor
    private init(id: UInt32, parent: NonLeafTreeNodeObject) {
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: parent, adaptiveWeight: 1, index: INDEX_BIND_LAST)
    }

    @MainActor
    static func new(id: UInt32, parent: NonLeafTreeNodeObject) -> BenchmarkFrameWindow {
        let window = BenchmarkFrameWindow(id: id, parent: parent)
        TestApp.shared._windows.append(window)
        return window
    }

    static func reset(delayNanoseconds: UInt64) {
        frameWriteCount = 0
        frameDelayNanoseconds = delayNanoseconds
    }

    override func closeAxWindow() {
        unbindFromParent()
    }

    @MainActor
    override var title: String {
        get async { "Window \(windowId)" }
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
        Self.frameWriteCount += 1
        if Self.frameDelayNanoseconds > 0 {
            usleep(useconds_t(Self.frameDelayNanoseconds / 1_000))
        }
        let currentRect = rect ?? Rect(topLeftX: topLeft?.x ?? 0, topLeftY: topLeft?.y ?? 0, width: size?.width ?? 0, height: size?.height ?? 0)
        rect = Rect(
            topLeftX: topLeft?.x ?? currentRect.topLeftX,
            topLeftY: topLeft?.y ?? currentRect.topLeftY,
            width: size?.width ?? currentRect.width,
            height: size?.height ?? currentRect.height,
        )
    }
}
