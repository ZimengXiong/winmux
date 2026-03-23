import TOMLKit

private let workspaceSidebarParser: [String: any ParserProtocol<WorkspaceSidebarConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "collapsed-width": Parser(\.collapsedWidth, parseWorkspaceSidebarWidth),
    "width": Parser(\.width, parseWorkspaceSidebarWidth),
    "monitor": Parser(\.monitor) { value, backtrace, errors in
        parseMonitorDescriptions(value, backtrace, &errors)
    },
    "workspace-labels": Parser(\.workspaceLabels, parseWorkspaceSidebarLabels),
]

func parseWorkspaceSidebar(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> WorkspaceSidebarConfig {
    parseTable(raw, WorkspaceSidebarConfig(), workspaceSidebarParser, backtrace, &errors)
}

private func parseWorkspaceSidebarWidth(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Int> {
    parseInt(raw, backtrace)
        .filter(.semantic(backtrace, "Must be greater than 0")) { $0 > 0 }
}

private func parseWorkspaceSidebarLabels(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> [String: String] {
    guard let rawTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return [:]
    }
    var result: [String: String] = [:]
    for (workspaceName, rawLabel) in rawTable {
        if let label = parseString(rawLabel, backtrace + .key(workspaceName)).getOrNil(appendErrorTo: &errors) {
            result[workspaceName] = label
        }
    }
    return result
}
