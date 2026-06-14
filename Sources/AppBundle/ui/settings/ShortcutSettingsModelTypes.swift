import Foundation

extension ShortcutSettingsModel {
    struct Action: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String?
        let commandScript: String
        let canonicalCommand: String
    }

    enum Category: String, CaseIterable, Identifiable {
        case managed = "Managed"
        case common = "Common"

        var id: String { rawValue }
    }

    struct Section: Identifiable, Hashable {
        let id: String
        let category: Category
        let title: String
        let summary: String?
        let actions: [Action]
    }

    struct Summary: Identifiable, Hashable {
        let id: String
        let notation: String
        let command: String
    }

    enum WorkspaceShortcutKind: String, CaseIterable, Identifiable {
        case switchTo
        case moveTo

        var id: String { rawValue }

        var title: String {
            switch self {
                case .switchTo: "Switch"
                case .moveTo: "Move"
            }
        }

        var subtitle: String {
            switch self {
                case .switchTo: "Change focus to workspace N"
                case .moveTo: "Send the focused window to workspace N"
            }
        }
    }

    struct WorkspaceOverride: Identifiable, Hashable {
        let workspaceName: String
        var switchNotation: String?
        var moveNotation: String?

        var id: String { workspaceName }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case shortcuts
        case advanced

        var id: String { rawValue }

        var title: String {
            switch self {
                case .shortcuts: "Shortcuts"
                case .advanced: "Advanced"
            }
        }
    }
}
