public struct RenameProjectCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .renameProject,
        allowInConfig: false,
        help: rename_project_help_generated,
        flags: [
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
            "--json": trueBoolFlag(\.json),
        ],
        posArgs: [
            newMandatoryPosArgParser(\.projectId, consumeStrCliArg, placeholder: "<project-id>"),
            newMandatoryPosArgParser(\.displayName, consumeStrCliArg, placeholder: "<project-name>"),
        ],
    )

    public var projectId: Lateinit<String> = .uninitialized
    public var displayName: Lateinit<String> = .uninitialized
    public var failIfNoop = false
    public var json = false
}

func parseRenameProjectCmdArgs(_ args: StrArrSlice) -> ParsedCmd<RenameProjectCmdArgs> {
    parseSpecificCmdArgs(RenameProjectCmdArgs(rawArgs: args), args)
}
