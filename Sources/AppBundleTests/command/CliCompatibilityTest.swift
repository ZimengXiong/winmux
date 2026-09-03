@testable import Cli
@testable import Common
import Foundation
import XCTest

final class CliCompatibilityTest: XCTestCase {
    func testUsageAndParseFailuresUseAeroSpaceExitCode() throws {
        let noArgs = try runCli([])
        XCTAssertEqual(noArgs.exitCode, 2)
        XCTAssertTrue(noArgs.stdout.isEmpty)
        XCTAssertTrue(noArgs.stderr.hasPrefix("USAGE:"))

        let parseFailure = try runCli(["not-a-command"])
        XCTAssertEqual(parseFailure.exitCode, 2)
        XCTAssertTrue(parseFailure.stdout.isEmpty)
        XCTAssertEqual(parseFailure.stderr, "Unrecognized subcommand 'not-a-command'\n")
    }

    func testDashDashStopsOptionAndHelpParsing() throws {
        let mode = try XCTUnwrap(parseCmdArgs(["mode", "--", "--help"]).cmdOrNil as? ModeCmdArgs)
        XCTAssertEqual(mode.targetMode.val, "--help")

        let singleDashMode = try XCTUnwrap(parseCmdArgs(["mode", "-"]).cmdOrNil as? ModeCmdArgs)
        XCTAssertEqual(singleDashMode.targetMode.val, "-")

        let trigger = try XCTUnwrap(
            parseCmdArgs(["trigger-binding", "--mode", "main", "--", "--help"]).cmdOrNil as? TriggerBindingCmdArgs,
        )
        XCTAssertEqual(trigger.mode, "main")
        XCTAssertEqual(trigger.binding.val, "--help")

        XCTAssertNotNil(parseCmdArgs(["mode", "--help"]).unwrap().1)
        XCTAssertEqual(
            parseCmdArgs(["workspace", "--", "foo", "--fail-if-noop"]).unwrap().2,
            "ERROR: Unknown argument '--fail-if-noop'",
        )
    }

    func testDashDashDisambiguatesControlWords() throws {
        let workspaceMove = try XCTUnwrap(
            parseCmdArgs(["move-node-to-workspace", "--", "new"]).cmdOrNil as? MoveNodeToWorkspaceCmdArgs,
        )
        switch workspaceMove.target.val {
            case .direct(let workspace): XCTAssertEqual(workspace.raw, "new")
            default: XCTFail("The sentinel must make 'new' a direct workspace name")
        }

        let focusMonitor = try XCTUnwrap(
            parseCmdArgs(["focus-monitor", "--", "next"]).cmdOrNil as? FocusMonitorCmdArgs,
        )
        assertMonitorPattern(focusMonitor.target.val, expected: "next")

        let moveNodeToMonitor = try XCTUnwrap(
            parseCmdArgs(["move-node-to-monitor", "--", "next"]).cmdOrNil as? MoveNodeToMonitorCmdArgs,
        )
        assertMonitorPattern(moveNodeToMonitor.target.val, expected: "next")

        let moveWorkspaceToMonitor = try XCTUnwrap(
            parseCmdArgs(["move-workspace-to-monitor", "--", "next"]).cmdOrNil as? MoveWorkspaceToMonitorCmdArgs,
        )
        assertMonitorPattern(moveWorkspaceToMonitor.target.val, expected: "next")

        XCTAssertEqual(
            parseCmdArgs(["workspace", "--", "next"]).unwrap().2,
            "ERROR: 'next' is a reserved workspace name",
        )
    }

    func testEveryPlumbedCommandAdvertisesDashDash() {
        let expectedHelpFragments = [
            (FocusMonitorCmdArgs.info.help, "[--] <monitor-pattern>..."),
            (ModeCmdArgs.info.help, "[--] <binding-mode>"),
            (MoveNodeToMonitorCmdArgs.info.help, "[--] <monitor-pattern>..."),
            (MoveNodeToWorkspaceCmdArgs.info.help, "[--] <workspace-name>"),
            (MoveWorkspaceToMonitorCmdArgs.info.help, "[--] <monitor-pattern>..."),
            (SummonWorkspaceCmdArgs.info.help, "[--] <workspace>"),
            (TriggerBindingCmdArgs.info.help, "[--] <binding>"),
            (WorkspaceCmdArgs.info.help, "[--] <workspace-name>"),
        ]

        for (help, fragment) in expectedHelpFragments {
            XCTAssertTrue(help.contains(fragment), "Missing \(fragment.singleQuoted) in:\n\(help)")
        }
    }

    private func assertMonitorPattern(
        _ target: MonitorTarget,
        expected: String,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        switch target {
            case .patterns(let patterns):
                guard case .pattern(let raw, _) = patterns.singleOrNil() else {
                    return XCTFail("Expected one monitor pattern", file: file, line: line)
                }
                XCTAssertEqual(raw, expected, file: file, line: line)
            default:
                XCTFail("The sentinel must make \(expected.singleQuoted) a monitor pattern", file: file, line: line)
        }
    }

    private func runCli(_ arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let executableUrl = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
            .appending(path: "winmux")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executableUrl.path))

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableUrl
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        )
    }
}
