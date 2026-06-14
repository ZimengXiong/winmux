import Common
import Foundation

extension ShortcutSettingsModel {
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
        collectMainBindings(workspaceNumbers: workspaceNumbers, assignments: &nextAssignments, customBindings: &nextCustomBindings)

        self.assignments = nextAssignments
        self.tapBindings = nextTapBindings()
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

    private func collectMainBindings(
        workspaceNumbers: [String],
        assignments nextAssignments: inout [String: String],
        customBindings nextCustomBindings: inout [Summary],
    ) {
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
    }

    private func nextTapBindings() -> [Summary] {
        config.modes[mainModeId]?.tapBindings.values.sorted {
            $0.descriptionWithKeyNotation < $1.descriptionWithKeyNotation
        }.map { binding in
            Summary(
                id: "tap:\(binding.descriptionWithKeyNotation)",
                notation: binding.descriptionWithKeyNotation,
                command: binding.commands.prettyDescription,
            )
        } ?? []
    }
}
