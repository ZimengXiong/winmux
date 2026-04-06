import Foundation

private let enableWindowManagementConfigKey = "enable-window-management"

func updateWindowManagementConfig(in configText: String, enabled: Bool) -> String {
    let lines = configText.components(separatedBy: "\n")
    let renderedValue = enabled ? "true" : "false"
    let firstSectionIndex = lines.firstIndex(where: isTomlSectionHeader)

    if let lineIndex = lines.firstIndex(where: { windowManagementConfigKey(in: $0) != nil }) {
        let originalLine = lines[lineIndex]
        let trailingComment = trailingTomlComment(in: originalLine)
            .map { " " + $0 }
            ?? ""
        let replacementLine = "\(enableWindowManagementConfigKey) = \(renderedValue)\(trailingComment)"

        if let firstSectionIndex, lineIndex >= firstSectionIndex {
            var resultLines = lines
            resultLines.remove(at: lineIndex)
            var prefixLines = Array(resultLines[..<firstSectionIndex])
            if !prefixLines.isEmpty, prefixLines.last?.isEmpty == false {
                prefixLines.append("")
            }
            prefixLines.append(replacementLine)
            prefixLines.append("")
            prefixLines.append(contentsOf: resultLines[firstSectionIndex...])
            return prefixLines.joined(separator: "\n")
        }

        var resultLines = lines
        let indentation = String(originalLine.prefix(while: { $0.isWhitespace }))
        resultLines[lineIndex] = "\(indentation)\(replacementLine)"
        return resultLines.joined(separator: "\n")
    }

    if let firstSectionIndex {
        var resultLines = Array(lines[..<firstSectionIndex])
        if !resultLines.isEmpty, resultLines.last?.isEmpty == false {
            resultLines.append("")
        }
        resultLines.append("\(enableWindowManagementConfigKey) = \(renderedValue)")
        resultLines.append("")
        resultLines.append(contentsOf: lines[firstSectionIndex...])
        return resultLines.joined(separator: "\n")
    }

    var result = configText
    if !result.isEmpty, !result.hasSuffix("\n") {
        result += "\n"
    }
    if !result.isEmpty {
        result += "\n"
    }
    result += "\(enableWindowManagementConfigKey) = \(renderedValue)"
    return result
}

@MainActor
func persistWindowManagementPreference(enabled: Bool) throws -> URL {
    let targetUrl = resolvedWindowManagementConfigUrl()
    let currentText = currentEditableConfigText(for: targetUrl)
    let updatedText = updateWindowManagementConfig(in: currentText, enabled: enabled)
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: .utf8)
    return targetUrl
}

@MainActor
private func resolvedWindowManagementConfigUrl() -> URL {
    preferredEditableConfigUrl()
}

@MainActor
private func currentEditableConfigText(for targetUrl: URL) -> String {
    if let text = try? String(contentsOf: targetUrl, encoding: .utf8) {
        return text
    }
    return starterConfigText()
}

private func windowManagementConfigKey(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty,
          !trimmed.hasPrefix("#"),
          let equals = trimmed.firstIndex(of: "=")
    else { return nil }
    let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
    return key == enableWindowManagementConfigKey ? String(key) : nil
}

private func trailingTomlComment(in line: String) -> String? {
    guard let hashIndex = line.firstIndex(of: "#") else { return nil }
    return String(line[hashIndex...]).trimmingCharacters(in: .whitespaces)
}

private func isTomlSectionHeader(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return (trimmed.hasPrefix("[[") && trimmed.hasSuffix("]]")) ||
        (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
}
