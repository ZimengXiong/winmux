public struct OpenSidebarCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .openSidebar,
        allowInConfig: true,
        help: """
        USAGE: open-sidebar

        Opens the workspace sidebar and arms type-to-search.
        """,
        flags: [:],
        posArgs: [],
    )
}
