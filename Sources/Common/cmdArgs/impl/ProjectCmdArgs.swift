public struct ProjectCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .project,
        allowInConfig: true,
        help: project_help_generated,
        flags: [
            "--project-id": explicitProjectIdFlag(\.explicitProjectId),
            "--wrap-around": optionalTrueBoolFlag(\._wrapAround),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
        ],
        posArgs: [optionalProjectTargetParser(\.target)],
    )

    public var target: Lateinit<ProjectTarget> = .uninitialized
    public var explicitProjectId: String?
    public var _wrapAround: Bool?
    public var failIfNoop: Bool = false
}

extension ProjectCmdArgs {
    public var wrapAround: Bool { _wrapAround ?? false }
}

func parseProjectCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ProjectCmdArgs> {
    parseSpecificCmdArgs(ProjectCmdArgs(rawArgs: args), args)
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
}

public enum ProjectTarget: Equatable, Sendable {
    case relative(NextPrev)
    case index(Int)
    case directId(String)

    public var isRelative: Bool {
        switch self {
            case .relative: true
            case .index, .directId: false
        }
    }
}

let projectTargetPlaceholder = "(<project-id>|<project-index>|next|prev)"

func optionalProjectTargetParser<Root>(
    _ keyPath: SendableWritableKeyPath<Root, Lateinit<ProjectTarget>>,
) -> PosArgParser<Root, Lateinit<ProjectTarget>> {
    ArgParser(keyPath) { input in
        parseProjectTarget(i: input).map { .initialized($0) }
    }
}

func explicitProjectIdFlag<Root>(
    _ keyPath: SendableWritableKeyPath<Root, String?>,
) -> SubArgParser<Root, String?> {
    ArgParser(keyPath) { input in
        guard let projectId = input.argOrNil else {
            return .fail("'<project-id>' is mandatory", advanceBy: 0)
        }
        return .succ(projectId, advanceBy: 1)
    }
}

func parseProjectTarget(i: PosArgParserInput) -> ParsedCliArgs<ProjectTarget> {
    switch i.arg {
        case "next": return ParsedCliArgs<ProjectTarget>.succ(.relative(.next), advanceBy: 1)
        case "prev": return ParsedCliArgs<ProjectTarget>.succ(.relative(.prev), advanceBy: 1)
        default:
            if let index = Int(i.arg), index > 0 {
                return ParsedCliArgs<ProjectTarget>.succ(.index(index), advanceBy: 1)
            }
            return ParsedCliArgs<ProjectTarget>.succ(.directId(i.arg), advanceBy: 1)
    }
}
