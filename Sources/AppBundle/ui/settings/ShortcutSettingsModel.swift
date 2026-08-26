import AppKit
import Foundation

@MainActor
public final class ShortcutSettingsModel: ObservableObject {
    public static let shared = ShortcutSettingsModel()

    @Published var selectedTab: Tab = .shortcuts
    @Published var sections: [Section] = []
    @Published var assignments: [String: String] = [:]
    @Published var tapBindings: [Summary] = []
    @Published var customBindings: [Summary] = []
    @Published var workspaceNumbers: [String] = []
    @Published var workspaceSwitchModifiers: NSEvent.ModifierFlags = defaultWorkspaceSwitchModifiers
    @Published var workspaceMoveModifiers: NSEvent.ModifierFlags = defaultWorkspaceMoveModifiers
    @Published var workspaceOverrides: [WorkspaceOverride] = []
    @Published public var openRequestId: Int = 0
    @Published var settingsRevision: Int = 0
    @Published var errorMessage: String? = nil

    var actionsById: [String: Action] = [:]
    var actionIdByCommand: [String: String] = [:]

    private init() {
        reload()
    }
}
