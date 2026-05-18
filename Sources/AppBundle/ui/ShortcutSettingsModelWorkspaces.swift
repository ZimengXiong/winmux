import AppKit
import Foundation
import MASShortcut

extension ShortcutSettingsModel {
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

    var workspaceManagedCommands: Set<String> {
        Set(workspaceNumbers.flatMap { workspaceName in
            [
                workspaceCommand(workspaceName, kind: .switchTo),
                workspaceCommand(workspaceName, kind: .moveTo),
            ]
        })
    }

    func workspacePatternModifiers(for kind: WorkspaceShortcutKind) -> NSEvent.ModifierFlags {
        switch kind {
            case .switchTo: workspaceSwitchModifiers
            case .moveTo: workspaceMoveModifiers
        }
    }

    func setWorkspacePatternModifiers(_ modifiers: NSEvent.ModifierFlags, kind: WorkspaceShortcutKind) {
        switch kind {
            case .switchTo:
                workspaceSwitchModifiers = modifiers
            case .moveTo:
                workspaceMoveModifiers = modifiers
        }
        persistBindings(assignments)
    }

    func workspaceOverrideNotation(for workspaceName: String, kind: WorkspaceShortcutKind) -> String? {
        guard let override = workspaceOverrides.first(where: { $0.workspaceName == workspaceName }) else { return nil }
        switch kind {
            case .switchTo: return override.switchNotation
            case .moveTo: return override.moveNotation
        }
    }
}
