protocol JsonFormattableListCmdArgs: Sendable {
    var _format: [StringInterToken] { get }
    var json: Bool { get }
}

extension ParsedCmd where T: JsonFormattableListCmdArgs {
    func validateJsonFormat() -> ParsedCmd<T> {
        flatMap { args in
            if args.json, let msg = getErrorIfFormatIsIncompatibleWithJson(args._format) {
                .failure(msg)
            } else {
                .cmd(args)
            }
        }
    }
}

public struct ListAppsCmdArgs: CmdArgs, JsonFormattableListCmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .listApps,
        allowInConfig: false,
        help: list_apps_help_generated,
        flags: [
            "--macos-native-hidden": boolFlag(\.macosHidden),

            // Formatting flags
            "--format": formatParser(\._format, for: .app),
            "--count": trueBoolFlag(\.outputOnlyCount),
            "--json": trueBoolFlag(\.json),
        ],
        posArgs: [],
        conflictingOptions: [
            ["--count", "--format"],
            ["--count", "--json"],
        ],
    )

    public var macosHidden: Bool?
    public var _format: [StringInterToken] = []
    public var outputOnlyCount: Bool = false
    public var json: Bool = false
}

extension ListAppsCmdArgs {
    public var format: [StringInterToken] {
        _format.isEmpty
            ? [
                .interVar("app-pid"), .interVar("right-padding"), .literal(" | "),
                .interVar("app-bundle-id"), .interVar("right-padding"), .literal(" | "),
                .interVar("app-name"),
            ]
            : _format
    }
}

func parseListAppsCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ListAppsCmdArgs> {
    parseSpecificCmdArgs(ListAppsCmdArgs(rawArgs: args), args)
        .validateJsonFormat()
}

func getErrorIfFormatIsIncompatibleWithJson(_ format: [StringInterToken]) -> String? {
    for x in format {
        switch x {
            case .interVar("right-padding"):
                return "%{right-padding} interpolation variable is not allowed when --json is used"
            case .interVar: break // skip
            case .literal(let literal):
                if literal.contains(where: { $0 != " " }) {
                    return "Only interpolation variables and spaces are allowed in '--format' when '--json' is used"
                }
        }
    }
    return nil
}
