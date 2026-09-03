public struct CreateProjectCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .createProject,
        allowInConfig: false,
        help: create_project_help_generated,
        flags: [
            "--name": singleValueSubArgParser(\.name, "<project-name>") { $0 },
            "--color": singleValueSubArgParser(\.color, "<#RRGGBB>") { $0 },
            "--json": trueBoolFlag(\.json),
        ],
        posArgs: [],
    )

    public var name: String?
    public var color: String?
    public var json = false
}

func parseCreateProjectCmdArgs(_ args: StrArrSlice) -> ParsedCmd<CreateProjectCmdArgs> {
    parseSpecificCmdArgs(CreateProjectCmdArgs(rawArgs: args), args)
}
