@testable import AppBundle
import Common
import XCTest

final class PostCommandRefreshBenchmarkTest: XCTestCase {
    @MainActor
    func testHotkeyBenchmark() async throws {
        try await runScenario(name: "safe-command", commands: [SafeBenchmarkCommand()])
        try await runScenario(name: "unsafe-command", commands: [UnsafeBenchmarkCommand()])
    }

    @MainActor
    private func runScenario(name: String, commands: [any Command]) async throws {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true

        var scheduledRefreshCount = 0
        let refreshDelayNanoseconds: UInt64 = 100_000_000
        setScheduledRefreshOverrideForTests { _, _ in
            scheduledRefreshCount += 1
            try await Task.sleep(nanoseconds: refreshDelayNanoseconds)
        }

        let iterations = 10
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< iterations {
            try await runLightSession(
                .hotkeyBinding,
                .forceRun,
                shouldSchedulePostRefresh: !commands.canSkipPostCommandRefresh
            ) {
                _ = try await commands.runCmdSeq(.defaultEnv, .emptyStdin)
            }
            try await waitForScheduledRefreshForTests()
        }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start

        let result = PostCommandRefreshBenchmarkResult(
            branch: ProcessInfo.processInfo.environment["POST_COMMAND_REFRESH_BENCHMARK_LABEL"] ?? "unknown",
            scenario: name,
            iterations: iterations,
            refreshDelayMilliseconds: Double(refreshDelayNanoseconds) / 1_000_000,
            scheduledRefreshCount: scheduledRefreshCount,
            elapsedMilliseconds: Double(elapsedNanoseconds) / 1_000_000,
        )
        print("POST_COMMAND_REFRESH_BENCHMARK \(result.json)")

        if commands.canSkipPostCommandRefresh {
            XCTAssertEqual(scheduledRefreshCount, 0)
        } else {
            XCTAssertEqual(scheduledRefreshCount, iterations)
        }

        setScheduledRefreshOverrideForTests(nil)
    }
}

private struct PostCommandRefreshBenchmarkResult: Codable {
    let branch: String
    let scenario: String
    let iterations: Int
    let refreshDelayMilliseconds: Double
    let scheduledRefreshCount: Int
    let elapsedMilliseconds: Double

    var json: String {
        String(data: try! JSONEncoder().encode(self), encoding: .utf8)!
    }
}

private struct SafeBenchmarkCommand: Command {
    typealias T = ListModesCmdArgs
    let args = ListModesCmdArgs(rawArgs: [])
    let shouldResetClosedWindowsCache = false
    let canSkipPostCommandRefresh = true

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        true
    }
}

private struct UnsafeBenchmarkCommand: Command {
    typealias T = ListModesCmdArgs
    let args = ListModesCmdArgs(rawArgs: [])
    let shouldResetClosedWindowsCache = false
    let canSkipPostCommandRefresh = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        true
    }
}
