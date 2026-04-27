private let agent_help = """
    USAGE: agent [-h|--help] query [--path <path>]
       OR: agent [-h|--help] check --path <path>
       OR: agent [-h|--help] apply --path <path>
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
        ],
        posArgs: [newMandatoryPosArgParser(\.subcommand, parseAgentSubcommand, placeholder: AgentSubcommand.unionLiteral)],
    )

    public var subcommand: Lateinit<AgentSubcommand> = .uninitialized
    public var path: String? = nil
}

public enum AgentSubcommand: String, CaseIterable, Equatable, Sendable {
    case query
    case check
    case apply
    case skill
}

func parseAgentCmdArgs(_ args: StrArrSlice) -> ParsedCmd<AgentCmdArgs> {
    parseSpecificCmdArgs(AgentCmdArgs(rawArgs: args), args)
        .filter("--path is mandatory for 'check' and 'apply'") {
            switch $0.subcommand.val {
                case .check, .apply: $0.path != nil
                case .query, .skill: true
            }
        }
        .filter("--path is incompatible with 'skill'") {
            $0.subcommand.val != .skill || $0.path == nil
        }
}

private func parseAgentSubcommand(i: PosArgParserInput) -> ParsedCliArgs<AgentSubcommand> {
    .init(parseEnum(i.arg, AgentSubcommand.self), advanceBy: 1)
}
