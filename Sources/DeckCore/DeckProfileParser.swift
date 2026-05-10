import Foundation
import TOMLKit

public enum DeckProfileParser {
    public static func parse(_ rawToml: String, sourceName: String? = nil) throws -> DeckProfile {
        let table = try TOMLTable(string: rawToml)
        var profile = try TOMLDecoder().decode(DeckProfile.self, from: table)
        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let sourceName {
            profile.name = sourceName
        }
        try validate(profile)
        return profile
    }

    public static func parseFile(_ url: URL) throws -> DeckProfile {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let sourceName = url.deletingPathExtension().lastPathComponent
        return try parse(raw, sourceName: sourceName)
    }

    public static func validate(_ profile: DeckProfile) throws {
        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DeckError.invalidProfile("Deck profile requires a non-empty 'name'.")
        }
        if profile.actions.isEmpty {
            throw DeckError.invalidProfile("Deck profile '\(profile.name)' must contain at least one [[actions]] entry.")
        }
        for (index, action) in profile.actions.enumerated() {
            let label = action.name ?? "actions[\(index)]"
            let type = try action.resolvedType()
            switch type {
                case .shell:
                    if action.run?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                        throw DeckError.invalidProfile("\(label): shell actions require 'run'.")
                    }
                case .app:
                    if action.app == nil && action.bundleId == nil {
                        throw DeckError.invalidProfile("\(label): app actions require 'app' or 'bundle-id'.")
                    }
                case .url:
                    if action.urls.isEmpty {
                        throw DeckError.invalidProfile("\(label): url actions require 'urls'.")
                    }
                case .file:
                    if action.paths.isEmpty {
                        throw DeckError.invalidProfile("\(label): file actions require 'path' or 'paths'.")
                    }
                case .browser:
                    if action.urls.isEmpty {
                        throw DeckError.invalidProfile("\(label): browser actions require 'urls'.")
                    }
                case .terminal:
                    if action.command?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                        throw DeckError.invalidProfile("\(label): terminal actions require 'command'.")
                    }
                case .bunch:
                    if action.name == nil && action.run == nil {
                        throw DeckError.invalidProfile("\(label): bunch actions require 'name' or 'run'.")
                    }
            }
            if let route = action.route, route.workspace == nil && route.tabGroup == nil {
                throw DeckError.invalidProfile("\(label): route requires 'workspace' or 'tab-group'.")
            }
        }
    }
}

public extension DeckAction {
    func resolvedType() throws -> DeckActionType {
        if let type { return type }
        if run != nil { return .shell }
        if command != nil { return .terminal }
        if !urls.isEmpty && (app != nil || profile != nil) { return .browser }
        if !urls.isEmpty { return .url }
        if !paths.isEmpty { return .file }
        if app != nil || bundleId != nil { return .app }
        throw DeckError.invalidProfile("\(name ?? "action"): cannot infer action type. Set 'type'.")
    }

    func effectiveMatch() -> DeckWindowMatch? {
        if let match, !match.isEmpty { return match }
        if let bundleId {
            return DeckWindowMatch(bundleId: bundleId)
        }
        if let app {
            let inferredBundle = DeckKnownApps.bundleId(forAppName: app)
            return DeckWindowMatch(bundleId: inferredBundle, appName: inferredBundle == nil ? app : nil)
        }
        if resolvedTypeOrNil == .browser {
            let browserApp = app ?? "Google Chrome"
            let inferredBundle = DeckKnownApps.bundleId(forAppName: browserApp)
            return DeckWindowMatch(bundleId: inferredBundle, appName: inferredBundle == nil ? browserApp : nil)
        }
        return nil
    }

    private var resolvedTypeOrNil: DeckActionType? {
        try? resolvedType()
    }
}

enum DeckKnownApps {
    static func bundleId(forAppName appName: String) -> String? {
        let normalized = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return switch normalized {
            case "chrome", "google chrome":
                "com.google.Chrome"
            case "safari":
                "com.apple.Safari"
            case "terminal":
                "com.apple.Terminal"
            case "iterm", "iterm2":
                "com.googlecode.iterm2"
            case "visual studio code", "vscode", "code":
                "com.microsoft.VSCode"
            case "cursor":
                "com.todesktop.230313mzl4w4u92"
            case "zed":
                "dev.zed.Zed"
            default:
                nil
        }
    }
}
