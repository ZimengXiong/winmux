import Foundation

public struct DeckStorage: Sendable {
    public let configDirectory: URL

    public init(configDirectory: URL = DeckStorage.defaultConfigDirectory()) {
        self.configDirectory = configDirectory
    }

    public static func defaultConfigDirectory() -> URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(filePath: xdg).appending(path: "deck")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config")
            .appending(path: "deck")
    }

    public var profilesDirectory: URL {
        configDirectory.appending(path: "profiles")
    }

    public func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
    }

    public func profileUrl(for argument: String) -> URL {
        let expanded = DeckPath.expandTilde(argument)
        if expanded.contains("/") || expanded.hasSuffix(".toml") {
            return URL(filePath: expanded)
        }
        return profilesDirectory.appending(path: "\(argument).toml")
    }

    public func loadProfile(_ argument: String) throws -> DeckProfile {
        let url = profileUrl(for: argument)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DeckError.profileNotFound("Deck profile not found: \(url.path)")
        }
        return try DeckProfileParser.parseFile(url)
    }

    public func listProfiles() throws -> [DeckProfileSummary] {
        guard FileManager.default.fileExists(atPath: profilesDirectory.path) else {
            return []
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: nil,
        )
        return urls
            .filter { $0.pathExtension == "toml" }
            .sortedByPath()
            .map { DeckProfileSummary(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
    }

    public func createStarterProfile(name: String, root: String?, force: Bool = false) throws -> URL {
        try ensureDirectories()
        let url = profileUrl(for: name)
        if FileManager.default.fileExists(atPath: url.path), !force {
            throw DeckError.invalidArguments("Deck profile already exists: \(url.path)")
        }
        let rootValue = root ?? "$HOME/Projects/\(name)"
        let text = DeckStorage.starterProfile(name: name, root: rootValue)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public static func starterProfile(name: String, root: String) -> String {
        """
        name = "\(name)"
        root = "\(root)"

        [env]
        PORT = "3000"

        [[actions]]
        name = "Editor"
        type = "shell"
        run = "code --new-window \\"$DECK_ROOT\\""

        [actions.route]
        workspace = "code"
        tab-group = "editor"
        timeout-seconds = 12

        [actions.match]
        bundle-id = "com.microsoft.VSCode"

        [[actions]]
        name = "Codex"
        type = "terminal"
        command = "codex"

        [actions.route]
        workspace = "code"
        tab-group = "agents"
        timeout-seconds = 12

        [actions.match]
        bundle-id = "com.apple.Terminal"
        title-contains = "\(name)"

        [[actions]]
        name = "Browser"
        type = "browser"
        app = "Google Chrome"
        profile = "Default"
        new-window = true
        urls = ["http://localhost:$PORT"]

        [actions.route]
        workspace = "browser"
        tab-group = "local"
        timeout-seconds = 12

        [actions.match]
        bundle-id = "com.google.Chrome"
        """
    }
}

public struct DeckProfileSummary: Equatable, Sendable {
    public let name: String
    public let url: URL
}

private extension Array where Element == URL {
    func sortedByPath() -> [URL] {
        sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
