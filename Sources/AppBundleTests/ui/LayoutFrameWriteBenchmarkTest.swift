@testable import AppBundle
import Common
import XCTest

final class LayoutFrameWriteBenchmarkTest: XCTestCase {
    @MainActor
    func testRepeatedLayoutBenchmark() async throws {
        // A hotkey relayout that changes no geometry must write each frame exactly once (the
        // first pass) and then reuse it. Regression guard: at this window count the float drift
        // in layoutTiles used to defeat the reuse check, making every idle pass rewrite every
        // window over AX. The count matters -- 2-5, 8 and 9 windows never drifted here.
        try await runScenario(name: "steady-hotkey", event: .hotkeyBinding, iterations: 10, expectedFrameWrites: 6)
        // A generic AX event means the window actually moved, so reasserting every pass is intended.
        try await runScenario(name: "steady-ax", event: .ax("benchmark"), iterations: 10, expectedFrameWrites: 60)
    }

    /// The reuse check has two failure directions and the scenarios above only cover one.
    /// Too tight a tolerance rewrites every frame on every idle pass; too loose a tolerance
    /// swallows a real move and the window silently stops following the layout. This locks
    /// the second direction: raising reusableFrameTolerance to a pixel-scale value fails here.
    @MainActor
    func testFrameReuseStillWritesAfterRealMove() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "layout-bench-real-move")
        workspace.rootTilingContainer.layout = .tiles
        for index in 0 ..< 6 {
            _ = BenchmarkFrameWindow.new(id: UInt32(index + 1), parent: workspace.rootTilingContainer)
        }
        XCTAssertTrue(workspace.focusWorkspace())
        BenchmarkFrameWindow.reset(delayNanoseconds: 0)

        try await $refreshSessionEvent.withValue(.hotkeyBinding) {
            try await workspace.layoutWorkspace()
            try await workspace.layoutWorkspace()
            XCTAssertEqual(BenchmarkFrameWindow.frameWriteCount, 6, "idle relayout must reuse frames")

            // One point is the smallest move the layout can actually express: AX positions are
            // whole points and setFrame reads back integral values.
            let first = workspace.rootTilingContainer.children.first!
            first.setWeight(.h, first.getWeight(.h) + 1)
            try await workspace.layoutWorkspace()
        }

        XCTAssertGreaterThan(
            BenchmarkFrameWindow.frameWriteCount, 6,
            "a one-point resize must reach AX, but the reuse check swallowed it",
        )
    }

    @MainActor
    private func runScenario(name: String, event: RefreshSessionEvent, iterations: Int, expectedFrameWrites: Int) async throws {
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

        XCTAssertEqual(BenchmarkFrameWindow.frameWriteCount, expectedFrameWrites, "scenario \(name)")
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
