import Common
import Foundation

let legacyConfigDotfileName = ".aerospace.toml"
let generatedConfigDirectoryName = "winmux"
let generatedConfigFileName = "winmux.toml"

func xdgConfigHomeUrl() -> URL {
    ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/")
}

func generatedConfigUrl() -> URL {
    xdgConfigHomeUrl()
        .appending(path: generatedConfigDirectoryName)
        .appending(path: generatedConfigFileName)
}

func legacyConfigCandidateUrls() -> [URL] {
    [
        xdgConfigHomeUrl().appending(path: "aerospace").appending(path: "aerospace.toml"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: legacyConfigDotfileName),
    ]
}

func preferredLegacyConfigImportUrl() -> URL? {
    legacyConfigCandidateUrls().first { FileManager.default.fileExists(atPath: $0.path) }
}

@MainActor
func preferredEditableConfigUrl() -> URL {
    if let configLocation = serverArgs.configLocation {
        return URL(filePath: configLocation)
    }
    if let customConfigUrl = findCustomConfigUrl().urlOrNil {
        return customConfigUrl
    }
    return generatedConfigUrl()
}

func starterConfigText() -> String {
    let starterBindings: [(String, String)] = [
        ("alt-space", "layout horizontal vertical"),
        ("alt-h", "focus left"),
        ("alt-j", "focus down"),
        ("alt-k", "focus up"),
        ("alt-l", "focus right"),
        ("alt-shift-h", "move left"),
        ("alt-shift-j", "move down"),
        ("alt-shift-k", "move up"),
        ("alt-shift-l", "move right"),
        ("cmd-shift-h", "join-with left"),
        ("cmd-shift-j", "join-with down"),
        ("cmd-shift-k", "join-with up"),
        ("cmd-shift-l", "join-with right"),
        ("alt-shift-t", "layout floating tiling"),
        ("alt-shift-m", "fullscreen"),
        ("ctrl-1", "workspace 1"),
        ("ctrl-2", "workspace 2"),
        ("ctrl-3", "workspace 3"),
        ("ctrl-4", "workspace 4"),
        ("ctrl-5", "workspace 5"),
        ("ctrl-6", "workspace 6"),
        ("ctrl-7", "workspace 7"),
        ("ctrl-8", "workspace 8"),
        ("ctrl-9", "workspace 9"),
        ("alt-shift-1", "move-node-to-workspace 1"),
        ("alt-shift-2", "move-node-to-workspace 2"),
        ("alt-shift-3", "move-node-to-workspace 3"),
        ("alt-shift-4", "move-node-to-workspace 4"),
        ("alt-shift-5", "move-node-to-workspace 5"),
        ("alt-shift-6", "move-node-to-workspace 6"),
        ("alt-shift-7", "move-node-to-workspace 7"),
        ("alt-shift-8", "move-node-to-workspace 8"),
        ("alt-shift-9", "move-node-to-workspace 9"),
    ]
    let bindingLines = starterBindings.map { key, command in
        "\(key) = '\(command)'"
    }.joined(separator: "\n")
    return """
        config-version = 2

        [mode.main.binding]
        \(bindingLines)
        """
}

@MainActor
func ensureBootstrapConfigExistsIfNeeded() throws -> URL? {
    guard serverArgs.configLocation == nil else { return nil }
    let targetUrl = generatedConfigUrl()
    let existingLegacyUrls = preferredLegacyConfigImportUrl().map { [$0] } ?? []
    if try materializeBootstrapConfigIfNeeded(targetUrl: targetUrl, existingLegacyUrls: existingLegacyUrls) {
        return targetUrl
    } else {
        return nil
    }
}

func materializeBootstrapConfigIfNeeded(targetUrl: URL, existingLegacyUrls: [URL]) throws -> Bool {
    guard !FileManager.default.fileExists(atPath: targetUrl.path) else { return false }
    let parentUrl = targetUrl.deletingLastPathComponent()
    if parentUrl.path != targetUrl.path {
        try FileManager.default.createDirectory(at: parentUrl, withIntermediateDirectories: true)
    }
    if let legacyUrl = existingLegacyUrls.first {
        try FileManager.default.copyItem(at: legacyUrl, to: targetUrl)
    } else {
        try starterConfigText().write(to: targetUrl, atomically: true, encoding: .utf8)
    }
    return true
}

func findCustomConfigUrl() -> ConfigFile {
    let candidates: [URL] = if let configLocation = serverArgs.configLocation {
        [URL(filePath: configLocation)]
    } else {
        [generatedConfigUrl()]
    }
    let existingCandidates: [URL] = candidates.filter { (candidate: URL) in FileManager.default.fileExists(atPath: candidate.path) }
    let count = existingCandidates.count
    return switch count {
        case 0: .noCustomConfigExists
        case 1: .file(existingCandidates.first.orDie())
        default: .ambiguousConfigError(existingCandidates)
    }
}

enum ConfigFile {
    case file(URL), ambiguousConfigError(_ candidates: [URL]), noCustomConfigExists

    var urlOrNil: URL? {
        return switch self {
            case .file(let url): url
            case .ambiguousConfigError, .noCustomConfigExists: nil
        }
    }
}
