public struct MoveNodeToProjectCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .moveNodeToProject,
        allowInConfig: true,
        help: move_node_to_project_help_generated,
        flags: [
            "--project-id": explicitProjectIdFlag(\.explicitProjectId),
            "--wrap-around": optionalTrueBoolFlag(\._wrapAround),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
            "--window-id": optionalWindowIdFlag(),
            "--focus-follows-window": trueBoolFlag(\.focusFollowsWindow),
        ],
        posArgs: [optionalProjectTargetParser(\.target)],
    )

    public var target: Lateinit<ProjectTarget> = .uninitialized
    public var explicitProjectId: String?
    public var _wrapAround: Bool?
    public var failIfNoop: Bool = false
    public var focusFollowsWindow: Bool = false
}

extension MoveNodeToProjectCmdArgs {
    public var wrapAround: Bool { _wrapAround ?? false }
}

func parseMoveNodeToProjectCmdArgs(_ args: StrArrSlice) -> ParsedCmd<MoveNodeToProjectCmdArgs> {
    parseSpecificCmdArgs(MoveNodeToProjectCmdArgs(rawArgs: args), args)
        .filter("Project target is mandatory (use a positional target or --project-id <project-id>)") {
            $0.target.isInitialized || $0.explicitProjectId != nil
        }
        .filterNot("--project-id is incompatible with a positional project target") {
            $0.target.isInitialized && $0.explicitProjectId != nil
        }
        .map { args in
            var args = args
            if let projectId = args.explicitProjectId {
                args.target = .initialized(.directId(projectId))
            }
            return args
        }
        .filter("--wrapAround requires using (next|prev) argument") { ($0._wrapAround != nil).implies($0.target.val.isRelative) }
        .filterNot("--fail-if-noop is incompatible with (next|prev)") { $0.failIfNoop && $0.target.val.isRelative }
        .filterNot("--window-id is incompatible with (next|prev)") { $0.windowId != nil && $0.target.val.isRelative }
}
