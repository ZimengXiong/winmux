import AppKit
import Common
import Foundation
import MASShortcut

extension ShortcutSettingsModel {
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

    func applyBindingNotation(_ notation: String, to actionId: String) {
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

    func persistBindings(_ updatedAssignments: [String: String]) {
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

    func customCommandConflict(for notation: String, excluding actionId: String) -> String? {
        guard let binding = config.modes[mainModeId]?.bindings.values.first(where: { $0.descriptionWithKeyNotation == notation }) else {
            return nil
        }
        let command = binding.commands.prettyDescription
        guard let boundActionId = actionIdByCommand[command] else {
            return command
        }
        return boundActionId == actionId ? nil : nil
    }
}
