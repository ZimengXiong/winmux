public struct FocusCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .focus,
        allowInConfig: true,
        help: focus_help_generated,
        flags: [
            "--ignore-floating": falseBoolFlag(\.floatingAsTiling),
            "--window-id": ArgParser(\.windowId, upcastArgParserFun(parseUInt32SubArg)),
            "--dfs-index": ArgParser(\.dfsIndex, upcastArgParserFun(parseUInt32SubArg)),
            "--tab-index": ArgParser(\.tabIndex, upcastArgParserFun(parseTabIndexSubArg)),

            "--boundaries": ArgParser(\.rawBoundaries, upcastArgParserFun(parseBoundaries)),
            "--boundaries-action": ArgParser(\.rawBoundariesAction, upcastArgParserFun(parseBoundariesAction)),
            "--wrap-around": trueBoolFlag(\.wrapAroundAlias),
        ],
        posArgs: [ArgParser(\.targetArg, upcastArgParserFun(parseFocusTargetArg))],
        conflictingOptions: [
            ["--wrap-around", "--boundaries-action"],
            ["--wrap-around", "--boundaries"],
        ],
    )

    public var rawBoundaries: Boundaries? = nil // todo cover boundaries wrapping with tests
    public var rawBoundariesAction: WhenBoundariesCrossed? = nil
    fileprivate var wrapAroundAlias: Bool = false
    public var dfsIndex: UInt32? = nil
    public var tabIndex: UInt32? = nil
    public var targetArg: FocusTargetArg? = nil
    public var floatingAsTiling: Bool = true

    public init(rawArgs: StrArrSlice, targetArg: FocusTargetArg) {
        self.commonState = .init(rawArgs)
        self.targetArg = targetArg
    }

    public init(rawArgs: StrArrSlice, windowId: UInt32) {
        self.commonState = .init(rawArgs)
        self.windowId = windowId
    }

    public init(rawArgs: StrArrSlice, dfsIndex: UInt32) {
        self.commonState = .init(rawArgs)
        self.dfsIndex = dfsIndex
    }

    public init(rawArgs: StrArrSlice, tabIndex: UInt32) {
        self.commonState = .init(rawArgs)
        self.tabIndex = tabIndex
    }

    public enum Boundaries: String, CaseIterable, Equatable, Sendable {
        case workspace
        case allMonitorsOuterFrame = "all-monitors-outer-frame"
    }
    public enum WhenBoundariesCrossed: String, CaseIterable, Equatable, Sendable {
        case stop = "stop"
        case fail = "fail"
        case wrapAroundTheWorkspace = "wrap-around-the-workspace"
        case wrapAroundAllMonitors = "wrap-around-all-monitors"
    }
}

public enum FocusCmdTarget {
    case direction(CardinalDirection)
    case windowId(UInt32)
    case dfsIndex(UInt32)
    case tabIndex(UInt32)
    case dfsRelative(DfsNextPrev)
    case tabRelative(TabNextPrev)

    var requiresWorkspaceBoundaries: Bool {
        switch self {
            case .dfsRelative, .tabRelative: true
            default: false
        }
    }
}

extension FocusCmdArgs {
    public var target: FocusCmdTarget {
        if let targetArg {
            return switch targetArg {
                case .direction(let dir): .direction(dir)
                case .dfsRelative(let nextPrev): .dfsRelative(nextPrev)
                case .tabRelative(let nextPrev): .tabRelative(nextPrev)
            }
        }
        if let windowId {
            return .windowId(windowId)
        }
        if let dfsIndex {
            return .dfsIndex(dfsIndex)
        }
        if let tabIndex {
            return .tabIndex(tabIndex)
        }
        die("Parser invariants are broken")
    }

    public var boundaries: Boundaries { rawBoundaries ?? .workspace }
    public var boundariesAction: WhenBoundariesCrossed {
        wrapAroundAlias ? .wrapAroundTheWorkspace : (rawBoundariesAction ?? .stop)
    }
}

func parseFocusCmdArgs(_ args: StrArrSlice) -> ParsedCmd<FocusCmdArgs> {
    return parseSpecificCmdArgs(FocusCmdArgs(rawArgs: args), args)
        .flatMap { (raw: FocusCmdArgs) -> ParsedCmd<FocusCmdArgs> in
            raw.boundaries == .workspace && raw.boundariesAction == .wrapAroundAllMonitors
                ? .failure("\(raw.boundaries.rawValue) and \(raw.boundariesAction.rawValue) is an invalid combination of values")
                : .cmd(raw)
        }
        .filter("Mandatory argument is missing. \(FocusTargetArg.unionLiteral), --window-id, --dfs-index or --tab-index is required") {
            $0.targetArg != nil || $0.windowId != nil || $0.dfsIndex != nil || $0.tabIndex != nil
        }
        .filter("--window-id is incompatible with other options") {
            $0.windowId == nil || $0 == FocusCmdArgs(rawArgs: args, windowId: $0.windowId.orDie())
        }
        .filter("--dfs-index is incompatible with other options") {
            $0.dfsIndex == nil || $0 == FocusCmdArgs(rawArgs: args, dfsIndex: $0.dfsIndex.orDie())
        }
        .filter("--tab-index is incompatible with other options") {
            $0.tabIndex == nil || $0 == FocusCmdArgs(rawArgs: args, tabIndex: $0.tabIndex.orDie())
        }
        .filter("(dfs-next|dfs-prev|tab-next|tab-prev) only supports --boundaries workspace") {
            $0.target.requiresWorkspaceBoundaries.implies($0.boundaries == .workspace)
        }
}

private func parseBoundariesAction(i: SubArgParserInput) -> ParsedCliArgs<FocusCmdArgs.WhenBoundariesCrossed> {
    if let arg = i.nonFlagArgOrNil() {
        return .init(parseEnum(arg, FocusCmdArgs.WhenBoundariesCrossed.self), advanceBy: 1)
    } else {
        return .fail("<action> is mandatory", advanceBy: 0)
    }
}

private func parseBoundaries(i: SubArgParserInput) -> ParsedCliArgs<FocusCmdArgs.Boundaries> {
    if let arg = i.nonFlagArgOrNil() {
        return .init(parseEnum(arg, FocusCmdArgs.Boundaries.self), advanceBy: 1)
    } else {
        return .fail("<boundary> is mandatory", advanceBy: 0)
    }
}

private func parseFocusTargetArg(i: PosArgParserInput) -> ParsedCliArgs<FocusTargetArg> {
    .init(parseEnum(i.arg, FocusTargetArg.self), advanceBy: 1)
}

private func parseTabIndexSubArg(i: SubArgParserInput) -> ParsedCliArgs<UInt32> {
    parseUInt32SubArg(i: i).flatMap { rawIndex in
        rawIndex > 0
            ? .succ(rawIndex, advanceBy: 1)
            : .fail("'\(i.superArg)' must be followed by UInt32 greater than zero", advanceBy: 1)
    }
}
