public struct ListProjectsCmdArgs: CmdArgs, JsonFormattableListCmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .listProjects,
        allowInConfig: false,
        help: list_projects_help_generated,
        flags: [
            "--focused": boolFlag(\.focused),
            "--visible": boolFlag(\.visible),
            "--format": formatParser(\._format, for: .project),
            "--count": trueBoolFlag(\.outputOnlyCount),
            "--json": trueBoolFlag(\.json),
        ],
        posArgs: [],
        conflictingOptions: [
            ["--count", "--format"],
            ["--count", "--json"],
        ],
    )

    public var focused: Bool?
    public var visible: Bool?
    public var _format: [StringInterToken] = []
    public var outputOnlyCount = false
    public var json = false
}

extension ListProjectsCmdArgs {
    public var format: [StringInterToken] {
        if !_format.isEmpty { return _format }
        if json {
            return FormatVar.ProjectFormatVar.allCases.map { .interVar($0.rawValue) }
        }
        return [
            .interVar("project-index"), .interVar("right-padding"), .literal(" | "),
            .interVar("project-id"), .interVar("right-padding"), .literal(" | "),
            .interVar("project-name"),
        ]
    }
}

func parseListProjectsCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ListProjectsCmdArgs> {
    parseSpecificCmdArgs(ListProjectsCmdArgs(rawArgs: args), args)
        .validateJsonFormat()
}
