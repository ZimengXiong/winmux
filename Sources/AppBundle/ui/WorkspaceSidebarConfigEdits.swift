import Foundation

func updateWorkspaceSidebarLabelConfig(
    in configText: String,
    workspaceName: String,
    label: String?,
) -> String {
    let sectionHeader = "[workspace-sidebar.workspace-labels]"
    let lines = configText.components(separatedBy: "\n")
    guard let sectionIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == sectionHeader }) else {
        guard let label else { return configText }
        var result = configText
        if !result.isEmpty, !result.hasSuffix("\n") {
            result += "\n"
        }
        if !result.isEmpty {
            result += "\n"
        }
        result += "\(sectionHeader)\n"
        result += tomlWorkspaceLabelLine(workspaceName: workspaceName, label: label)
        return result
    }

    let sectionEnd = lines[(sectionIndex + 1)...]
        .firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        }) ?? lines.endIndex

    var resultLines = Array(lines[..<sectionIndex])
    resultLines.append(lines[sectionIndex])

    var wroteLabel = false
    var bodyLines: [String] = []
    for line in lines[(sectionIndex + 1)..<sectionEnd] {
        if workspaceSidebarLabelKey(in: line) == workspaceName {
            if let label, !wroteLabel {
                bodyLines.append(tomlWorkspaceLabelLine(workspaceName: workspaceName, label: label))
                wroteLabel = true
            }
            continue
        }
        bodyLines.append(line)
    }
    if let label, !wroteLabel {
        bodyLines.append(tomlWorkspaceLabelLine(workspaceName: workspaceName, label: label))
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
private func preferredWorkspaceSidebarConfigUrl() -> URL {
    preferredEditableConfigUrl()
}

private func workspaceSidebarLabelKey(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
    let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
    if key.hasPrefix("\""), key.hasSuffix("\""), key.count >= 2 {
        let inner = key.dropFirst().dropLast()
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
    return String(key)
}

private func tomlWorkspaceLabelLine(workspaceName: String, label: String) -> String {
    "\"\(tomlEscape(workspaceName))\" = \"\(tomlEscape(label))\""
}

private func tomlEscape(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
