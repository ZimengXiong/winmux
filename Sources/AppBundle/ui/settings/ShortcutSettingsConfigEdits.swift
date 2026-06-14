import Common
import Foundation

func updateModeBindingConfig(
    in configText: String,
    modeName: String = mainModeId,
    tableKey: String = "binding",
    managedCommands: Set<String>,
    assignments: [String: String],
) -> String {
    let sectionHeader = "[mode.\(modeName).\(tableKey)]"
    let lines = configText.components(separatedBy: "\n")
    let renderedAssignments = assignments
        .sorted { $0.key < $1.key }
        .map { tomlModeBindingLine(notation: $0.key, command: $0.value) }

    guard let sectionIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == sectionHeader }) else {
        guard !renderedAssignments.isEmpty else { return configText }
        var result = configText
        if !result.isEmpty, !result.hasSuffix("\n") {
            result += "\n"
        }
        if !result.isEmpty {
            result += "\n"
        }
        result += "\(sectionHeader)\n"
        result += renderedAssignments.joined(separator: "\n")
        return result
    }

    let sectionEnd = lines[(sectionIndex + 1)...]
        .firstIndex(where: isTomlSectionHeader)
        ?? lines.endIndex

    var resultLines = Array(lines[..<sectionIndex])
    var bodyLines: [String] = []
    for line in lines[(sectionIndex + 1)..<sectionEnd] {
        if let entry = parseTomlStringAssignment(line) {
            let command = canonicalConfigCommandScript(entry.value) ?? entry.value
            if assignments.keys.contains(entry.key) || managedCommands.contains(command) {
                continue
            }
        }
        bodyLines.append(line)
    }
    bodyLines.append(contentsOf: renderedAssignments)

    if bodyLines.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
        resultLines.append(sectionHeader)
        resultLines.append(contentsOf: bodyLines)
    } else if !resultLines.isEmpty, resultLines.last?.isEmpty == false {
        resultLines.append("")
    }
    resultLines.append(contentsOf: lines[sectionEnd...])
    return resultLines.joined(separator: "\n")
}

@MainActor
func readMainModeBindingEntries() -> [String: String] {
    let targetUrl = preferredShortcutSettingsConfigUrl()
    let currentText = currentShortcutSettingsConfigText(for: targetUrl)
    return readModeBindingEntries(in: currentText, modeName: mainModeId, tableKey: "binding")
}

func readModeBindingEntries(
    in configText: String,
    modeName: String = mainModeId,
    tableKey: String = "binding",
) -> [String: String] {
    let sectionHeader = "[mode.\(modeName).\(tableKey)]"
    let lines = configText.components(separatedBy: "\n")
    guard let sectionIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == sectionHeader }) else {
        return [:]
    }
    let sectionEnd = lines[(sectionIndex + 1)...]
        .firstIndex(where: isTomlSectionHeader)
        ?? lines.endIndex
    var result: [String: String] = [:]
    for line in lines[(sectionIndex + 1)..<sectionEnd] {
        if let entry = parseTomlStringAssignment(line) {
            result[entry.key] = entry.value
        }
    }
    return result
}

@MainActor
func persistMainModeBindings(assignments: [String: String], managedCommands: Set<String>) throws -> URL {
    let targetUrl = preferredShortcutSettingsConfigUrl()
    let currentText = currentShortcutSettingsConfigText(for: targetUrl)
    let updatedText = updateModeBindingConfig(
        in: currentText,
        modeName: mainModeId,
        tableKey: "binding",
        managedCommands: managedCommands,
        assignments: assignments,
    )
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: String.Encoding.utf8)
    return targetUrl
}

func canonicalConfigCommandScript(_ raw: String) -> String? {
    switch parseCommand(raw) {
        case .cmd(let command):
            command.args.description
        case .help, .failure:
            nil
    }
}

@MainActor
private func preferredShortcutSettingsConfigUrl() -> URL {
    preferredEditableConfigUrl()
}

@MainActor
private func currentShortcutSettingsConfigText(for targetUrl: URL) -> String {
    if let text = try? String(contentsOf: targetUrl, encoding: .utf8) {
        return text
    }
    return starterConfigText()
}

private struct TomlStringAssignment {
    let key: String
    let value: String
}

private func parseTomlStringAssignment(_ line: String) -> TomlStringAssignment? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
    let rawKey = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
    let rawValue = stripTomlInlineComment(String(trimmed[trimmed.index(after: equals)...]))
        .trimmingCharacters(in: .whitespaces)
    guard let key = parseTomlKey(rawKey), let value = parseTomlStringLiteral(rawValue) else { return nil }
    return TomlStringAssignment(key: key, value: value)
}

private func stripTomlInlineComment(_ raw: String) -> String {
    var result = ""
    var inSingle = false
    var inDouble = false
    var escaped = false
    for char in raw {
        if escaped {
            result.append(char)
            escaped = false
            continue
        }
        if inDouble, char == "\\" {
            result.append(char)
            escaped = true
            continue
        }
        if char == "\"" && !inSingle {
            inDouble.toggle()
        } else if char == "'" && !inDouble {
            inSingle.toggle()
        } else if char == "#", !inSingle, !inDouble {
            break
        }
        result.append(char)
    }
    return result
}

private func parseTomlKey(_ rawKey: String) -> String? {
    if let key = parseTomlStringLiteral(rawKey) {
        return key
    }
    guard !rawKey.isEmpty else { return nil }
    return rawKey
}

private func parseTomlStringLiteral(_ rawValue: String) -> String? {
    guard rawValue.count >= 2 else { return nil }
    if rawValue.first == "'", rawValue.last == "'" {
        return String(rawValue.dropFirst().dropLast())
    }
    guard rawValue.first == "\"", rawValue.last == "\"" else { return nil }
    let inner = rawValue.dropFirst().dropLast()
    var result = ""
    var escaped = false
    for char in inner {
        if escaped {
            switch char {
                case "\\":
                    result.append("\\")
                case "\"":
                    result.append("\"")
                case "n":
                    result.append("\n")
                case "r":
                    result.append("\r")
                case "t":
                    result.append("\t")
                default:
                    result.append(char)
            }
            escaped = false
            continue
        }
        if char == "\\" {
            escaped = true
        } else {
            result.append(char)
        }
    }
    return escaped ? nil : result
}

private func tomlModeBindingLine(notation: String, command: String) -> String {
    "\(renderTomlKey(notation)) = \"\(tomlDoubleQuoteEscape(command))\""
}

private func renderTomlKey(_ raw: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return raw.unicodeScalars.allSatisfy { allowed.contains($0) }
        ? raw
        : "\"\(tomlDoubleQuoteEscape(raw))\""
}

private func tomlDoubleQuoteEscape(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
}

private func isTomlSectionHeader(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return (trimmed.hasPrefix("[[") && trimmed.hasSuffix("]]")) ||
        (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
}
