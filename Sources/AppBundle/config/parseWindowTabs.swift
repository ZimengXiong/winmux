import TOMLKit

private let windowTabsParser: [String: any ParserProtocol<WindowTabsConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "height": Parser(\.height, parseWindowTabsHeight),
]

func parseWindowTabs(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> WindowTabsConfig {
    parseTable(raw, WindowTabsConfig(), windowTabsParser, backtrace, &errors)
}

private func parseWindowTabsHeight(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Int> {
    parseInt(raw, backtrace)
        .filter(.semantic(backtrace, "Must be greater than 20")) { $0 > 20 }
}
