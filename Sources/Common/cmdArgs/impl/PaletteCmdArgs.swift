public struct PaletteCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .palette,
        allowInConfig: true,
        help: """
            USAGE: palette [-h|--help]

            Toggle the window switcher palette: fuzzy-search all windows across all
            workspaces and projects, Enter to jump to the selected window.
            """,
        flags: [:],
        posArgs: [],
    )
}
