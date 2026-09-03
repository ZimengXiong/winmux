public struct SetProjectColorCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .setProjectColor,
        allowInConfig: false,
        help: set_project_color_help_generated,
        flags: [
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
            "--json": trueBoolFlag(\.json),
        ],
        posArgs: [
            newMandatoryPosArgParser(\.projectId, consumeStrCliArg, placeholder: "<project-id>"),
            newMandatoryPosArgParser(\.color, consumeStrCliArg, placeholder: "(<#RRGGBB>|auto)"),
        ],
    )

    public var projectId: Lateinit<String> = .uninitialized
    public var color: Lateinit<String> = .uninitialized
    public var failIfNoop = false
    public var json = false
}

func parseSetProjectColorCmdArgs(_ args: StrArrSlice) -> ParsedCmd<SetProjectColorCmdArgs> {
    parseSpecificCmdArgs(SetProjectColorCmdArgs(rawArgs: args), args)
}
