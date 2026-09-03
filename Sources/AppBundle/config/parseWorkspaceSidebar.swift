import Foundation
import TOMLKit

private let workspaceSidebarParser: [String: any ParserProtocol<WorkspaceSidebarConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "enable-focus": Parser(\.enableFocus, parseBool),
    "stay-on-top": Parser(\.stayOnTop, parseBool),
    "auto-hide": Parser(\.autoHide, parseBool),
    "always-expanded": Parser(\.alwaysExpanded, parseBool),
    "collapsed-width": Parser(\.collapsedWidth, parseWorkspaceSidebarWidth),
    "width": Parser(\.width, parseWorkspaceSidebarWidth),
    "monitor": Parser(\.monitor) { value, backtrace, errors in
        parseMonitorDescriptions(value, backtrace, &errors)
    },
    "show-status-pills": Parser(\.showStatusPills, parseBool),
    "show-clock": Parser(\.showClock, parseBool),
    "show-seconds": Parser(\.showSeconds, parseBool),
    "show-date": Parser(\.showDate, parseBool),
    "show-weekday": Parser(\.showWeekday, parseBool),
    "chrome-style": Parser(\.chromeStyle, parseChromeStyle),
    "solid-chrome-color": Parser(\.solidChromeColor, parseChromeSolidColor),
    "solid-chrome-custom-color": Parser(\.solidChromeCustomColor, parseChromeSolidCustomColor),
    "use-liquid-glass": Parser(\.chromeStyle) { raw, backtrace in
        parseBool(raw, backtrace).map { $0 ? .liquidGlass : .solid }
    },
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
    var parsed = parseTable(raw, WorkspaceSidebarConfig(), workspaceSidebarParser, backtrace, &errors)
    // Preserve the legacy key only when the modern setting is absent. This makes the
    // Appearance setting authoritative for configs that contain both keys.
    if let modernRawValue = raw.table?["chrome-style"]?.string,
       let modernStyle = ChromeStyle(rawValue: modernRawValue)
    {
        parsed.chromeStyle = modernStyle
    }
    if parsed.alwaysExpanded, parsed.width <= parsed.collapsedWidth {
        errors += [.semantic(
            backtrace + .key("width"),
            "Must be greater than collapsed-width when always-expanded is true",
        )]
    }
    return parsed
}

private func parseChromeSolidCustomColor(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<String> {
    parseString(raw, backtrace).flatMap { rawValue in
        normalizedWorkspaceSidebarColorHex(rawValue).orFailure(.semantic(backtrace, "Use a six-digit hex color, such as #1A2B3C"))
    }
}

private func parseChromeStyle(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<ChromeStyle> {
    parseString(raw, backtrace).flatMap { rawValue in
        ChromeStyle(rawValue: rawValue).orFailure(.semantic(
            backtrace,
            "Possible values: \(ChromeStyle.allCases.map(\.rawValue).joined(separator: ", "))",
        ))
    }
}

private func parseChromeSolidColor(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<ChromeSolidColor> {
    parseString(raw, backtrace).flatMap { rawValue in
        ChromeSolidColor(rawValue: rawValue).orFailure(.semantic(
            backtrace,
            "Possible values: \(ChromeSolidColor.allCases.map(\.rawValue).joined(separator: ", "))",
        ))
    }
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
