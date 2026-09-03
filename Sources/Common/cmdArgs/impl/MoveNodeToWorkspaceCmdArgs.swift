public struct MoveNodeToWorkspaceCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public static let parser: CmdParser<Self> = .init(
        kind: .moveNodeToWorkspace,
        allowInConfig: true,
        help: move_node_to_workspace_help_generated,
        flags: [
            "--wrap-around": optionalTrueBoolFlag(\._wrapAround),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
            "--window-id": optionalWindowIdFlag(),
            "--focus-follows-window": trueBoolFlag(\.focusFollowsWindow),

            "--stdin": optionalTrueBoolFlag(\.explicitStdinFlag),
            "--no-stdin": optionalFalseBoolFlag(\.explicitStdinFlag),
        ],
        posArgs: [
            dashDashArg(mandatory: false),
            newMandatoryPosArgParser(\.target, parseMoveNodeToWorkspaceTarget, placeholder: moveNodeToWorkspaceTargetPlaceholder),
        ],
        conflictingOptions: [
            ["--stdin", "--no-stdin"],
        ],
    )

    public var _wrapAround: Bool?
    public var explicitStdinFlag: Bool? = nil
    public var failIfNoop: Bool = false
    public var focusFollowsWindow: Bool = false
    public var target: Lateinit<MoveNodeToWorkspaceTarget> = .uninitialized

    public init(rawArgs: StrArrSlice) {
        self.commonState = .init(rawArgs)
    }
}

public enum MoveNodeToWorkspaceTarget: Equatable, Sendable {
    case newWorkspace
    case relative(NextPrev)
    case direct(WorkspaceName)

    public var isRelative: Bool {
        switch self {
            case .relative: true
            case .newWorkspace, .direct: false
        }
    }

    public func workspaceNameOrNil() -> WorkspaceName? {
        switch self {
            case .direct(let name): name
            case .newWorkspace, .relative: nil
        }
    }
}

private let moveNodeToWorkspaceTargetPlaceholder = "(<workspace-name>|new|next|prev)"

private func parseMoveNodeToWorkspaceTarget(i: PosArgParserInput) -> ParsedCliArgs<MoveNodeToWorkspaceTarget> {
    switch (i.arg, i.sawDashDash) {
        case ("new", false): .succ(.newWorkspace, advanceBy: 1)
        case ("next", false): .succ(.relative(.next), advanceBy: 1)
        case ("prev", false): .succ(.relative(.prev), advanceBy: 1)
        default: .init(WorkspaceName.parse(i.arg).map(MoveNodeToWorkspaceTarget.direct), advanceBy: 1)
    }
}

extension MoveNodeToWorkspaceCmdArgs {
    public var wrapAround: Bool { _wrapAround ?? false }
    public var useStdin: Bool { explicitStdinFlag ?? false }
}

func parseMoveNodeToWorkspaceCmdArgs(_ args: StrArrSlice) -> ParsedCmd<MoveNodeToWorkspaceCmdArgs> {
    parseSpecificCmdArgs(MoveNodeToWorkspaceCmdArgs(rawArgs: args), args)
        .filter("--wrapAround requires using (prev|next) argument") { ($0._wrapAround != nil).implies($0.target.val.isRelative) }
        .filterNot("--fail-if-noop is incompatible with (next|prev)") { $0.failIfNoop && $0.target.val.isRelative }
        .filterNot("--window-id is incompatible with (next|prev)") { $0.windowId != nil && $0.target.val.isRelative }
        .filter("--stdin and --no-stdin require using \(NextPrev.unionLiteral) argument") { ($0.explicitStdinFlag != nil).implies($0.target.val.isRelative) }
}
