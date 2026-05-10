import Foundation
import TOMLKit

private let workspaceSidebarParser: [String: any ParserProtocol<WorkspaceSidebarConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "collapsed-width": Parser(\.collapsedWidth, parseWorkspaceSidebarWidth),
    "width": Parser(\.width, parseWorkspaceSidebarWidth),
    "monitor": Parser(\.monitor) { value, backtrace, errors in
        parseMonitorDescriptions(value, backtrace, &errors)
    },
    "show-status-pills": Parser(\.showStatusPills, parseBool),
    "show-date": Parser(\.showDate, parseBool),
    "menu-bar-reserve-height": Parser(\.menuBarReserveHeight, parseWorkspaceSidebarMenuBarReserveHeight),
    "project-deletion-action": Parser(\.projectDeletionAction, parseWorkspaceProjectDeletionAction),
    "workspace-labels": Parser(\.workspaceLabels, parseWorkspaceSidebarLabels),
    "project-labels": Parser(\.projectLabels, parseWorkspaceSidebarLabels),
    "project-colors": Parser(\.projectColors, parseWorkspaceSidebarProjectColors),
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

private func parseWorkspaceSidebarMenuBarReserveHeight(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Int> {
    parseInt(raw, backtrace)
        .filter(.semantic(backtrace, "Must be greater than or equal to 0")) { $0 >= 0 }
}

private func parseWorkspaceProjectDeletionAction(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
) -> ParsedToml<WorkspaceProjectDeletionAction> {
    parseString(raw, backtrace).flatMap { rawValue in
        WorkspaceProjectDeletionAction(rawValue: rawValue)
            .orFailure(.semantic(
                backtrace,
                "Possible values: \(WorkspaceProjectDeletionAction.allCases.map(\.rawValue).joined(separator: ", "))",
            ))
    }
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

func normalizedWorkspaceSidebarColorHex(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    let allowedCharacters = Set("0123456789abcdefABCDEF")
    guard hex.count == 6,
          hex.allSatisfy({ allowedCharacters.contains($0) })
    else {
        return nil
    }
    return "#\(hex.uppercased())"
}

private func parseWorkspaceSidebarProjectColors(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> [String: String] {
    guard let rawTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return [:]
    }
    var result: [String: String] = [:]
    for (projectId, rawColor) in rawTable {
        let colorBacktrace = backtrace + .key(projectId)
        guard let color = parseString(rawColor, colorBacktrace).getOrNil(appendErrorTo: &errors) else { continue }
        guard let normalized = normalizedWorkspaceSidebarColorHex(color) else {
            errors.append(.semantic(colorBacktrace, "Must be a hex color like '#RRGGBB'"))
            continue
        }
        result[projectId] = normalized
    }
    return result
}
