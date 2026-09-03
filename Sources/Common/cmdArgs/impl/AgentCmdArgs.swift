private let agent_help = """
    USAGE: agent [-h|--help] query [--path <path>]
       OR: agent [-h|--help] check (--path <path>|--stdin)
       OR: agent [-h|--help] apply (--path <path>|--stdin)
       OR: agent [-h|--help] skill
    """

public struct AgentCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .agent,
        allowInConfig: false,
        help: agent_help,
        flags: [
            "--path": singleValueSubArgParser(\.path, "<path>") { $0 },
            "--stdin": trueBoolFlag(\.useStdin),
        ],
        posArgs: [newMandatoryPosArgParser(\.subcommand, parseAgentSubcommand, placeholder: AgentSubcommand.unionLiteral)],
        conflictingOptions: [
            ["--path", "--stdin"],
        ],
    )

    public var subcommand: Lateinit<AgentSubcommand> = .uninitialized
    public var path: String? = nil
    public var useStdin: Bool = false
}

public enum AgentSubcommand: String, CaseIterable, Equatable, Sendable {
    case query
    case check
    case apply
    case skill
}

func parseAgentCmdArgs(_ args: StrArrSlice) -> ParsedCmd<AgentCmdArgs> {
    parseSpecificCmdArgs(AgentCmdArgs(rawArgs: args), args)
        .filter("--path or --stdin is mandatory for 'check' and 'apply'") {
            switch $0.subcommand.val {
                case .check, .apply: $0.path != nil || $0.useStdin
                case .query, .skill: true
            }
        }
        .filter("--path is incompatible with 'skill'") {
            $0.subcommand.val != .skill || $0.path == nil
        }
        .filter("--stdin is incompatible with 'query' and 'skill'") {
            switch $0.subcommand.val {
                case .check, .apply: true
                case .query, .skill: !$0.useStdin
            }
        }
}

private func parseAgentSubcommand(i: PosArgParserInput) -> ParsedCliArgs<AgentSubcommand> {
    .init(parseEnum(i.arg, AgentSubcommand.self), advanceBy: 1)
}
