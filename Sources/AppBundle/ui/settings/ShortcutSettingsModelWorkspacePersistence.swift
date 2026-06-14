import Common
import Foundation

extension ShortcutSettingsModel {
    func setWorkspaceOverrideNotation(_ notation: String?, workspaceName: String, kind: WorkspaceShortcutKind) {
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

    func renderedManagedAssignments(from updatedAssignments: [String: String]) throws -> [String: String] {
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

    func customWorkspaceConflict(for notation: String, workspaceName: String, kind: WorkspaceShortcutKind) -> String? {
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
