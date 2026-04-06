import AppKit
import Common

protocol Command: AeroAny, Equatable, Sendable {
    associatedtype T where T: CmdArgs
    var args: T { get }
    @MainActor
    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool

    /// We should refresh closedWindowsCache when the command can change the tree or visible workspace assignment
    var shouldResetClosedWindowsCache: Bool { get }

    /// Some commands fully update the in-memory model and only need the light-session layout/UI pass.
    /// Native macOS state transitions or arbitrary side effects should keep the follow-up full refresh.
    var canSkipPostCommandRefresh: Bool { get }
}

extension Command {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.args.equals(rhs.args)
    }

    nonisolated func equals(_ other: any Command) -> Bool {
        (other as? Self).flatMap { self == $0 } ?? false
    }
}

extension Command {
    var info: CmdStaticInfo { T.info }
}

extension Command {
    var canSkipPostCommandRefresh: Bool {
        switch self {
            case is BalanceSizesCommand,
                 is ConfigCommand,
                 is DebugWindowsCommand,
                 is FlattenWorkspaceTreeCommand,
                 is FocusBackAndForthCommand,
                 is FocusCommand,
                 is FocusMonitorCommand,
                 is FullscreenCommand,
                 is JoinWithCommand,
                 is LayoutCommand,
                 is ListAppsCommand,
                 is ListExecEnvVarsCommand,
                 is ListModesCommand,
                 is ListMonitorsCommand,
                 is ListWindowsCommand,
                 is ListWorkspacesCommand,
                 is ModeCommand,
                 is MoveCommand,
                 is MoveMouseCommand,
                 is MoveNodeToMonitorCommand,
                 is MoveNodeToWorkspaceCommand,
                 is MoveWorkspaceToMonitorCommand,
                 is ResizeCommand,
                 is SnapCommand,
                 is SplitCommand,
                 is StackWithCommand,
                 is SummonWorkspaceCommand,
                 is SwapCommand,
                 is VolumeCommand,
                 is WorkspaceBackAndForthCommand,
                 is WorkspaceCommand:
                true
            default:
                false
        }
    }

    @MainActor
    @discardableResult
    func run(_ env: CmdEnv, _ stdin: consuming CmdStdin) async throws -> CmdResult {
        return try await [self].runCmdSeq(env, stdin)
    }

    var isExec: Bool { self is ExecAndForgetCommand }
}

// There are 4 entry points for running commands:
// 1. config keybindings
// 2. CLI requests to server
// 3. on-window-detected callback
// 4. Tray icon buttons
extension [Command] {
    var canSkipPostCommandRefresh: Bool {
        allSatisfy(\.canSkipPostCommandRefresh)
    }

    @MainActor
    func runCmdSeq(_ env: CmdEnv, _ io: sending CmdIo) async throws -> Bool {
        var isSucc = true
        for command in self {
            let commandSucc = try await command.run(env, io)
            isSucc = commandSucc && isSucc
            refreshModel()
            if commandSucc && command.shouldResetClosedWindowsCache {
                syncClosedWindowsCacheToCurrentWorld()
            }
        }
        return isSucc
    }

    @MainActor
    func runCmdSeq(_ env: CmdEnv, _ stdin: consuming CmdStdin) async throws -> CmdResult {
        let io: CmdIo = CmdIo(stdin: stdin)
        let isSucc = try await runCmdSeq(env, io)
        return CmdResult(stdout: io.stdout, stderr: io.stderr, exitCode: isSucc ? 0 : 1)
    }
}
