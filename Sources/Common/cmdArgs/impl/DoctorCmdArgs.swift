public struct DoctorCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .doctor,
        allowInConfig: false,
        help: """
            USAGE: doctor [-h|--help]

            Print diagnostics: permissions, monitors, per-app accessibility latency,
            and window manager state. Useful for bug reports and performance triage.
            """,
        flags: [:],
        posArgs: [],
    )
}
