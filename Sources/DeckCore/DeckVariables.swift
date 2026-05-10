import Foundation

public enum DeckPath {
    public static func expandTilde(_ path: String) -> String {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appending(path: String(path.dropFirst(2)))
                .path
        }
        return path
    }

    public static func absolutize(_ path: String, relativeTo base: String?) -> String {
        let expanded = expandTilde(path)
        if expanded.hasPrefix("/") { return expanded }
        if let base {
            return URL(filePath: base).appending(path: expanded).path
        }
        return URL(filePath: FileManager.default.currentDirectoryPath).appending(path: expanded).path
    }
}

public struct DeckVariableResolver: Sendable {
    public let variables: [String: String]

    public init(profile: DeckProfile, profileUrl: URL? = nil) {
        var variables = ProcessInfo.processInfo.environment
        let root = profile.root
            .map(DeckPath.expandTilde)
            .map { Self.expand($0, using: variables) }
        variables["DECK_NAME"] = profile.name
        variables["DECK_ROOT"] = root
        variables["PROJECT_ROOT"] = root
        if let profileUrl {
            variables["DECK_PROFILE"] = profileUrl.path
            variables["DECK_PROFILE_DIR"] = profileUrl.deletingLastPathComponent().path
        }
        for (key, value) in profile.env {
            variables[key] = Self.expand(value, using: variables)
        }
        self.variables = variables
    }

    public func expand(_ value: String) -> String {
        DeckVariableResolver.expand(value, using: variables)
    }

    public static func expand(_ value: String, using variables: [String: String]) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            let char = value[index]
            guard char == "$" else {
                result.append(char)
                index = value.index(after: index)
                continue
            }
            let next = value.index(after: index)
            guard next < value.endIndex else {
                result.append(char)
                index = next
                continue
            }
            if value[next] == "{" {
                let nameStart = value.index(after: next)
                guard let close = value[nameStart...].firstIndex(of: "}") else {
                    result.append(char)
                    index = next
                    continue
                }
                let name = String(value[nameStart..<close])
                result += variables[name] ?? ""
                index = value.index(after: close)
                continue
            }
            if isVariableNameStart(value[next]) {
                var end = next
                while end < value.endIndex, isVariableNameContinuation(value[end]) {
                    end = value.index(after: end)
                }
                let name = String(value[next..<end])
                result += variables[name] ?? ""
                index = end
                continue
            }
            result.append(char)
            index = next
        }
        return result
    }
}

private func isVariableNameStart(_ char: Character) -> Bool {
    char == "_" || char.isLetter
}

private func isVariableNameContinuation(_ char: Character) -> Bool {
    isVariableNameStart(char) || char.isNumber
}
