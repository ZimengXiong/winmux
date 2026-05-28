public struct ProjectCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .project,
        allowInConfig: true,
        help: project_help_generated,
        flags: [
            "--wrap-around": optionalTrueBoolFlag(\._wrapAround),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
        ],
        posArgs: [newMandatoryPosArgParser(\.target, parseProjectTarget, placeholder: projectTargetPlaceholder)],
    )

    public var target: Lateinit<ProjectTarget> = .uninitialized
    public var _wrapAround: Bool?
    public var failIfNoop: Bool = false
}

extension ProjectCmdArgs {
    public var wrapAround: Bool { _wrapAround ?? false }
}

func parseProjectCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ProjectCmdArgs> {
    parseSpecificCmdArgs(ProjectCmdArgs(rawArgs: args), args)
        .filter("--wrapAround requires using (next|prev) argument") { ($0._wrapAround != nil).implies($0.target.val.isRelative) }
        .filterNot("--fail-if-noop is incompatible with (next|prev)") { $0.failIfNoop && $0.target.val.isRelative }
}

public enum ProjectTarget: Equatable, Sendable {
    case relative(NextPrev)
    case index(Int)

    public var isRelative: Bool {
        switch self {
            case .relative: true
            case .index: false
        }
    }
}

let projectTargetPlaceholder = "(<project-index>|next|prev)"

func parseProjectTarget(i: PosArgParserInput) -> ParsedCliArgs<ProjectTarget> {
    switch i.arg {
        case "next": return ParsedCliArgs<ProjectTarget>.succ(.relative(.next), advanceBy: 1)
        case "prev": return ParsedCliArgs<ProjectTarget>.succ(.relative(.prev), advanceBy: 1)
        default:
            guard let index = Int(i.arg), index > 0 else {
                return .fail("Can't parse project target '\(i.arg)'. Expected \(projectTargetPlaceholder)", advanceBy: 1)
            }
            return ParsedCliArgs<ProjectTarget>.succ(.index(index), advanceBy: 1)
    }
}
