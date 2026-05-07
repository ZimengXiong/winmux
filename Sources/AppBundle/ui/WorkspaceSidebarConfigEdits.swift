import Foundation

private let workspaceSidebarSectionHeader = "[workspace-sidebar]"
private let workspaceSidebarMenuBarReserveKey = "menu-bar-reserve-height"

func updateWorkspaceSidebarMenuBarReserveConfig(
    in configText: String,
    height: Int,
) -> String {
    let renderedValue = "\(height)"
    let lines = configText.components(separatedBy: "\n")
    guard let sectionIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == workspaceSidebarSectionHeader }) else {
        var result = configText
        if !result.isEmpty, !result.hasSuffix("\n") {
            result += "\n"
        }
        if !result.isEmpty {
            result += "\n"
        }
        result += "\(workspaceSidebarSectionHeader)\n"
        result += "    \(workspaceSidebarMenuBarReserveKey) = \(renderedValue)"
        return result
    }

    let sectionEnd = lines[(sectionIndex + 1)...]
        .firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        }) ?? lines.endIndex

    var resultLines = lines
    for lineIndex in (sectionIndex + 1)..<sectionEnd {
        guard workspaceSidebarConfigKey(in: resultLines[lineIndex]) == workspaceSidebarMenuBarReserveKey else { continue }
        let indentation = String(resultLines[lineIndex].prefix(while: { $0.isWhitespace }))
        let trailingComment = trailingTomlComment(in: resultLines[lineIndex]).map { " " + $0 } ?? ""
        resultLines[lineIndex] = "\(indentation)\(workspaceSidebarMenuBarReserveKey) = \(renderedValue)\(trailingComment)"
        return resultLines.joined(separator: "\n")
    }

    resultLines.insert("    \(workspaceSidebarMenuBarReserveKey) = \(renderedValue)", at: sectionIndex + 1)
    return resultLines.joined(separator: "\n")
}

@MainActor
func persistWorkspaceSidebarMenuBarReserveHeight(_ height: Int) throws -> URL {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    let currentText = (try? String(contentsOf: targetUrl, encoding: .utf8)) ?? starterConfigText()
    let updatedText = updateWorkspaceSidebarMenuBarReserveConfig(in: currentText, height: height)
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: .utf8)
    return targetUrl
}

func updateWorkspaceSidebarLabelConfig(
    in configText: String,
    workspaceName: String,
    label: String?,
) -> String {
    updateWorkspaceSidebarKeyValueSectionConfig(
        in: configText,
        sectionHeader: "[workspace-sidebar.workspace-labels]",
        key: workspaceName,
        value: label,
    )
}

func updateWorkspaceSidebarProjectLabelConfig(
    in configText: String,
    projectId: String,
    label: String?,
) -> String {
    updateWorkspaceSidebarKeyValueSectionConfig(
        in: configText,
        sectionHeader: "[workspace-sidebar.project-labels]",
        key: projectId,
        value: label,
    )
}

private func updateWorkspaceSidebarKeyValueSectionConfig(
    in configText: String,
    sectionHeader: String,
    key: String,
    value: String?,
) -> String {
    let lines = configText.components(separatedBy: "\n")
    guard let sectionIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == sectionHeader }) else {
        guard let value else { return configText }
        var result = configText
        if !result.isEmpty, !result.hasSuffix("\n") {
            result += "\n"
        }
        if !result.isEmpty {
            result += "\n"
        }
        result += "\(sectionHeader)\n"
        result += tomlWorkspaceSidebarKeyValueLine(key: key, value: value)
        return result
    }

    let sectionEnd = lines[(sectionIndex + 1)...]
        .firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        }) ?? lines.endIndex

    var resultLines = Array(lines[..<sectionIndex])
    resultLines.append(lines[sectionIndex])

    var wroteValue = false
    var bodyLines: [String] = []
    for line in lines[(sectionIndex + 1)..<sectionEnd] {
        if workspaceSidebarLabelKey(in: line) == key {
            if let value, !wroteValue {
                bodyLines.append(tomlWorkspaceSidebarKeyValueLine(key: key, value: value))
                wroteValue = true
            }
            continue
        }
        bodyLines.append(line)
    }
    if let value, !wroteValue {
        bodyLines.append(tomlWorkspaceSidebarKeyValueLine(key: key, value: value))
    }

    let hasAnyEntries = bodyLines.contains(where: { workspaceSidebarLabelKey(in: $0) != nil })
    if hasAnyEntries {
        resultLines.append(contentsOf: bodyLines)
    } else {
        resultLines.removeLast()
        if !resultLines.isEmpty, resultLines.last?.isEmpty == false {
            resultLines.append("")
        }
    }
    resultLines.append(contentsOf: lines[sectionEnd...])
    return resultLines.joined(separator: "\n")
}

@MainActor
func persistWorkspaceSidebarLabel(workspaceName: String, label: String?) throws {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    let currentText = (try? String(contentsOf: targetUrl, encoding: .utf8)) ?? ""
    let updatedText = updateWorkspaceSidebarLabelConfig(
        in: currentText,
        workspaceName: workspaceName,
        label: label,
    )
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: .utf8)
}

@MainActor
func persistWorkspaceSidebarProjectLabel(projectId: String, label: String?) throws {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    let currentText = (try? String(contentsOf: targetUrl, encoding: .utf8)) ?? ""
    let updatedText = updateWorkspaceSidebarProjectLabelConfig(
        in: currentText,
        projectId: projectId,
        label: label,
    )
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: .utf8)
}

@MainActor
private func preferredWorkspaceSidebarConfigUrl() -> URL {
    preferredEditableConfigUrl()
}

private func workspaceSidebarLabelKey(in line: String) -> String? {
    workspaceSidebarConfigKey(in: line)
}

private func workspaceSidebarConfigKey(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
    let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
    if key.hasPrefix("\""), key.hasSuffix("\""), key.count >= 2 {
        let inner = key.dropFirst().dropLast()
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
    return String(key)
}

private func trailingTomlComment(in line: String) -> String? {
    guard let hashIndex = line.firstIndex(of: "#") else { return nil }
    return String(line[hashIndex...]).trimmingCharacters(in: .whitespaces)
}

private func tomlWorkspaceSidebarKeyValueLine(key: String, value: String) -> String {
    "\"\(tomlEscape(key))\" = \"\(tomlEscape(value))\""
}

private func tomlEscape(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
