public enum DeleteProjectAction: String, CaseIterable, Equatable, Sendable {
    case moveWindowsToFallback = "move-windows-to-fallback"
}

public struct DeleteProjectCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .deleteProject,
        allowInConfig: false,
        help: delete_project_help_generated,
        flags: [
            "--action": ArgParser(\.action, parseDeleteProjectAction),
            "--if-window-count": ArgParser(\.ifWindowCount, upcastArgParserFun(parseUInt32SubArg)),
            "--json": trueBoolFlag(\.json),
        ],
        posArgs: [newMandatoryPosArgParser(\.projectId, consumeStrCliArg, placeholder: "<project-id>")],
    )

    public var projectId: Lateinit<String> = .uninitialized
    public var action: DeleteProjectAction?
    public var ifWindowCount: UInt32?
    public var json = false
}

func parseDeleteProjectCmdArgs(_ args: StrArrSlice) -> ParsedCmd<DeleteProjectCmdArgs> {
    parseSpecificCmdArgs(DeleteProjectCmdArgs(rawArgs: args), args)
        .filter("Mandatory option is not specified (--action)") { $0.action != nil }
        .filter("Mandatory option is not specified (--if-window-count)") { $0.ifWindowCount != nil }
}

private func parseDeleteProjectAction(_ input: SubArgParserInput) -> ParsedCliArgs<DeleteProjectAction?> {
    guard let raw = input.nonFlagArgOrNil() else {
        return .fail("'\(DeleteProjectAction.unionLiteral)' is mandatory", advanceBy: 0)
    }
    guard let action = DeleteProjectAction(rawValue: raw) else {
        return .fail(
            "Can't parse '\(raw)'. Possible values: \(DeleteProjectAction.unionLiteral)",
            advanceBy: 1,
        )
    }
    return .succ(action, advanceBy: 1)
}
