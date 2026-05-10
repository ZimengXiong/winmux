import AppKit
import Common
import Foundation
import HotKey
import MASShortcut

@MainActor
public final class ShortcutSettingsModel: ObservableObject {
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
        case unmanaged = "Unmanaged"

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

    public static let shared = ShortcutSettingsModel()

    @Published var selectedTab: Tab = .shortcuts
    @Published private(set) var sections: [Section] = []
    @Published private(set) var assignments: [String: String] = [:]
    @Published private(set) var tapBindings: [Summary] = []
    @Published private(set) var customBindings: [Summary] = []
    @Published private(set) var workspaceNumbers: [String] = []
    @Published private(set) var workspaceSwitchModifiers: NSEvent.ModifierFlags = defaultWorkspaceSwitchModifiers
    @Published private(set) var workspaceMoveModifiers: NSEvent.ModifierFlags = defaultWorkspaceMoveModifiers
    @Published private(set) var workspaceOverrides: [WorkspaceOverride] = []
    @Published public private(set) var openRequestId: Int = 0
    @Published var errorMessage: String? = nil

    private var actionsById: [String: Action] = [:]
    private var actionIdByCommand: [String: String] = [:]

    private init() {
        reload()
    }

    var managedCommands: Set<String> {
        Set(actionsById.values.map(\.canonicalCommand)).union(workspaceManagedCommands)
    }

    func bindingNotation(for actionId: String) -> String? {
        assignments[actionId]
    }

    func shortcutValue(for actionId: String) -> MASShortcut? {
        guard let notation = bindingNotation(for: actionId) else { return nil }
        return masShortcut(from: notation)
    }

    func setShortcutValue(_ shortcut: MASShortcut?, for actionId: String) {
        errorMessage = nil
        if let shortcut, let notation = notation(from: shortcut) {
            applyBindingNotation(notation, to: actionId)
        } else {
            clearBinding(for: actionId)
        }
    }

    func clearBinding(for actionId: String) {
        errorMessage = nil
        var updatedAssignments = assignments
        updatedAssignments[actionId] = nil
        persistBindings(updatedAssignments)
    }

    func workspacePatternIncludesModifier(_ modifier: NSEvent.ModifierFlags, kind: WorkspaceShortcutKind) -> Bool {
        workspacePatternModifiers(for: kind).contains(modifier)
    }

    func setWorkspacePatternModifier(
        _ modifier: NSEvent.ModifierFlags,
        enabled: Bool,
        kind: WorkspaceShortcutKind
    ) {
        errorMessage = nil
        var updatedModifiers = workspacePatternModifiers(for: kind)
        if enabled {
            updatedModifiers.insert(modifier)
        } else {
            updatedModifiers.remove(modifier)
        }
        setWorkspacePatternModifiers(updatedModifiers, kind: kind)
    }

    func workspacePatternNotation(for kind: WorkspaceShortcutKind, workspaceName: String) -> String? {
        guard let key = workspaceKey(for: workspaceName) else { return nil }
        let modifiers = workspacePatternModifiers(for: kind)
        return renderBindingNotation(modifiers: modifiers, key: key)
    }

    func workspacePatternDisplay(for kind: WorkspaceShortcutKind) -> String {
        let previewWorkspace = workspaceNumbers.first ?? "1"
        return workspaceEffectiveNotation(for: previewWorkspace, kind: kind)
            .map(displayBindingNotation) ?? "None"
    }

    func workspaceOverrideShortcutValue(workspaceName: String, kind: WorkspaceShortcutKind) -> MASShortcut? {
        guard let notation = workspaceOverrideNotation(for: workspaceName, kind: kind) else { return nil }
        return masShortcut(from: notation)
    }

    func setWorkspaceOverrideShortcutValue(
        _ shortcut: MASShortcut?,
        workspaceName: String,
        kind: WorkspaceShortcutKind
    ) {
        errorMessage = nil
        let notation = shortcut.flatMap(notation(from:))
        setWorkspaceOverrideNotation(notation, workspaceName: workspaceName, kind: kind)
    }

    func clearWorkspaceOverride(workspaceName: String, kind: WorkspaceShortcutKind) {
        errorMessage = nil
        setWorkspaceOverrideNotation(nil, workspaceName: workspaceName, kind: kind)
    }

    func workspaceEffectiveNotation(for workspaceName: String, kind: WorkspaceShortcutKind) -> String? {
        workspaceOverrideNotation(for: workspaceName, kind: kind)
            ?? workspacePatternNotation(for: kind, workspaceName: workspaceName)
    }

    func reload() {
        let workspaceNumbers = shortcutSettingsWorkspaceNumbers()
        let sections = buildShortcutSections()
        self.sections = sections
        self.workspaceNumbers = workspaceNumbers
        let actions = sections.flatMap(\.actions)
        self.actionsById = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        self.actionIdByCommand = Dictionary(uniqueKeysWithValues: actions.map { ($0.canonicalCommand, $0.id) })

        var nextAssignments: [String: String] = [:]
        var nextCustomBindings: [Summary] = []
        let mainBindingEntries = config.modes[mainModeId]?.bindings.values.map {
            (notation: $0.descriptionWithKeyNotation, command: $0.commands.prettyDescription)
        } ?? []
        let workspaceState = inferWorkspaceShortcutState(
            from: Dictionary(uniqueKeysWithValues: mainBindingEntries.map { ($0.notation, $0.command) }),
            workspaceNumbers: workspaceNumbers,
            defaultSwitchModifiers: defaultWorkspaceSwitchModifiers,
            defaultMoveModifiers: defaultWorkspaceMoveModifiers,
        )
        let mainBindings = config.modes[mainModeId]?.bindings.values.sorted {
            $0.descriptionWithKeyNotation < $1.descriptionWithKeyNotation
        } ?? []
        for binding in mainBindings {
            let command = binding.commands.prettyDescription
            if parseWorkspaceCommandTarget(command, kind: .switchTo).flatMap({ workspaceNumbers.contains($0) ? $0 : nil }) != nil {
                continue
            }
            if parseWorkspaceCommandTarget(command, kind: .moveTo).flatMap({ workspaceNumbers.contains($0) ? $0 : nil }) != nil {
                continue
            }
            if let actionId = actionIdByCommand[command] {
                nextAssignments[actionId] = binding.descriptionWithKeyNotation
            } else {
                nextCustomBindings.append(.init(
                    id: "binding:\(binding.descriptionWithKeyNotation)",
                    notation: binding.descriptionWithKeyNotation,
                    command: command,
                ))
            }
        }

        let nextTapBindings = config.modes[mainModeId]?.tapBindings.values.sorted {
            $0.descriptionWithKeyNotation < $1.descriptionWithKeyNotation
        }.map { binding in
            Summary(
                id: "tap:\(binding.descriptionWithKeyNotation)",
                notation: binding.descriptionWithKeyNotation,
                command: binding.commands.prettyDescription,
            )
        } ?? []

        self.assignments = nextAssignments
        self.tapBindings = nextTapBindings
        self.customBindings = nextCustomBindings
        self.workspaceSwitchModifiers = workspaceState.switchModifiers
        self.workspaceMoveModifiers = workspaceState.moveModifiers
        self.workspaceOverrides = workspaceNumbers.map {
            WorkspaceOverride(
                workspaceName: $0,
                switchNotation: workspaceState.switchOverrides[$0],
                moveNotation: workspaceState.moveOverrides[$0],
            )
        }
    }

    func requestWindowOpen() {
        reload()
        openRequestId += 1
    }

    private func applyBindingNotation(_ notation: String, to actionId: String) {
        if let conflict = customCommandConflict(for: notation, excluding: actionId) {
            errorMessage = "'\(notation)' is already used by custom binding: \(conflict)"
            reload()
            return
        }

        var updatedAssignments = assignments
        for (otherActionId, otherNotation) in assignments where otherActionId != actionId && otherNotation == notation {
            updatedAssignments[otherActionId] = nil
        }
        updatedAssignments[actionId] = notation
        persistBindings(updatedAssignments)
    }

    private func persistBindings(_ updatedAssignments: [String: String]) {
        assignments = updatedAssignments
        Task { @MainActor in
            do {
                let renderedAssignments = try renderedManagedAssignments(from: updatedAssignments)
                let targetUrl = try persistMainModeBindings(
                    assignments: renderedAssignments,
                    managedCommands: managedCommands,
                )
                let isOk = try await reloadConfig(forceConfigUrl: targetUrl)
                if isOk {
                    reload()
                }
            } catch {
                errorMessage = error.localizedDescription
                reload()
            }
        }
    }

    private func customCommandConflict(for notation: String, excluding actionId: String) -> String? {
        guard let binding = config.modes[mainModeId]?.bindings.values.first(where: { $0.descriptionWithKeyNotation == notation }) else {
            return nil
        }
        let command = binding.commands.prettyDescription
        guard let boundActionId = actionIdByCommand[command] else {
            return command
        }
        return boundActionId == actionId ? nil : nil
    }

    private var workspaceManagedCommands: Set<String> {
        Set(workspaceNumbers.flatMap { workspaceName in
            [
                workspaceCommand(workspaceName, kind: .switchTo),
                workspaceCommand(workspaceName, kind: .moveTo),
            ]
        })
    }

    private func workspacePatternModifiers(for kind: WorkspaceShortcutKind) -> NSEvent.ModifierFlags {
        switch kind {
            case .switchTo: workspaceSwitchModifiers
            case .moveTo: workspaceMoveModifiers
        }
    }

    private func setWorkspacePatternModifiers(_ modifiers: NSEvent.ModifierFlags, kind: WorkspaceShortcutKind) {
        switch kind {
            case .switchTo:
                workspaceSwitchModifiers = modifiers
            case .moveTo:
                workspaceMoveModifiers = modifiers
        }
        persistBindings(assignments)
    }

    private func workspaceOverrideNotation(for workspaceName: String, kind: WorkspaceShortcutKind) -> String? {
        guard let override = workspaceOverrides.first(where: { $0.workspaceName == workspaceName }) else { return nil }
        switch kind {
            case .switchTo: return override.switchNotation
            case .moveTo: return override.moveNotation
        }
    }

    private func setWorkspaceOverrideNotation(_ notation: String?, workspaceName: String, kind: WorkspaceShortcutKind) {
        if let conflict = notation.flatMap({ customWorkspaceConflict(for: $0, workspaceName: workspaceName, kind: kind) }) {
            errorMessage = "'\((notation ?? ""))' is already used by custom binding: \(conflict)"
            reload()
            return
        }

        workspaceOverrides = workspaceOverrides.map { current in
            guard current.workspaceName == workspaceName else { return current }
            var updated = current
            switch kind {
                case .switchTo: updated.switchNotation = notation
                case .moveTo: updated.moveNotation = notation
            }
            return updated
        }
        persistBindings(assignments)
    }

    private func renderedManagedAssignments(from updatedAssignments: [String: String]) throws -> [String: String] {
        var generatedPairs: [(notation: String, command: String)] = updatedAssignments.compactMap { actionId, notation in
            guard let action = actionsById[actionId] else { return nil }
            return (notation, action.canonicalCommand)
        }

        let overrideMap = Dictionary(uniqueKeysWithValues: workspaceOverrides.map { ($0.workspaceName, $0) })
        for workspaceName in workspaceNumbers {
            if let notation = overrideMap[workspaceName]?.switchNotation ?? workspacePatternNotation(for: .switchTo, workspaceName: workspaceName) {
                generatedPairs.append((notation, workspaceCommand(workspaceName, kind: .switchTo)))
            }
            if let notation = overrideMap[workspaceName]?.moveNotation ?? workspacePatternNotation(for: .moveTo, workspaceName: workspaceName) {
                generatedPairs.append((notation, workspaceCommand(workspaceName, kind: .moveTo)))
            }
        }

        var renderedAssignments: [String: String] = [:]
        for pair in generatedPairs {
            if let existingCommand = renderedAssignments[pair.notation], existingCommand != pair.command {
                throw shortcutSettingsError("'\(pair.notation)' is assigned to both '\(existingCommand)' and '\(pair.command)'")
            }
            renderedAssignments[pair.notation] = pair.command
        }

        if let mainModeBindings = config.modes[mainModeId]?.bindings.values {
            for binding in mainModeBindings {
                let command = binding.commands.prettyDescription
                if managedCommands.contains(command) {
                    continue
                }
                let notation = binding.descriptionWithKeyNotation
                if let candidateCommand = renderedAssignments[notation], candidateCommand != command {
                    throw shortcutSettingsError("'\(notation)' is already used by custom binding: \(command)")
                }
            }
        }
        return renderedAssignments
    }

    private func customWorkspaceConflict(for notation: String, workspaceName: String, kind: WorkspaceShortcutKind) -> String? {
        let commandForNotation = config.modes[mainModeId]?.bindings.values
            .first(where: { $0.descriptionWithKeyNotation == notation })?
            .commands.prettyDescription
        guard let commandForNotation else { return nil }
        let managedWorkspaceCommand = workspaceCommand(workspaceName, kind: kind)
        if managedCommands.contains(commandForNotation) {
            return commandForNotation == managedWorkspaceCommand ? nil : nil
        }
        return commandForNotation
    }
}
