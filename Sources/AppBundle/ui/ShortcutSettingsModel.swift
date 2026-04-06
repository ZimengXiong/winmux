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

@MainActor
private func buildShortcutSections() -> [ShortcutSettingsModel.Section] {
    return [
        .init(
            id: "managed-focus",
            category: .managed,
            title: "Focus",
            summary: "Directional focus movement while WinMux is managing windows.",
            actions: [
                shortcutAction(id: "focus-left", title: "Focus Left", command: "focus left"),
                shortcutAction(id: "focus-down", title: "Focus Down", command: "focus down"),
                shortcutAction(id: "focus-up", title: "Focus Up", command: "focus up"),
                shortcutAction(id: "focus-right", title: "Focus Right", command: "focus right"),
            ],
        ),
        .init(
            id: "managed-move",
            category: .managed,
            title: "Move",
            summary: "Reposition the focused tiled window inside the tree.",
            actions: [
                shortcutAction(id: "move-left", title: "Move Left", command: "move left"),
                shortcutAction(id: "move-down", title: "Move Down", command: "move down"),
                shortcutAction(id: "move-up", title: "Move Up", command: "move up"),
                shortcutAction(id: "move-right", title: "Move Right", command: "move right"),
            ],
        ),
        .init(
            id: "managed-splits",
            category: .managed,
            title: "Splits",
            summary: "Create a shared split container with the nearest window in the chosen direction.",
            actions: [
                shortcutAction(id: "split-left", title: "Split Left", command: "join-with left"),
                shortcutAction(id: "split-down", title: "Split Down", command: "join-with down"),
                shortcutAction(id: "split-up", title: "Split Up", command: "join-with up"),
                shortcutAction(id: "split-right", title: "Split Right", command: "join-with right"),
            ],
        ),
        .init(
            id: "managed-layout",
            category: .managed,
            title: "Layout",
            summary: "Common layout toggles for managed windows.",
            actions: [
                shortcutAction(
                    id: "toggle-floating",
                    title: "Toggle Floating",
                    subtitle: "Switch the focused managed window between floating and tiling.",
                    command: "layout floating tiling"
                ),
                shortcutAction(
                    id: "fullscreen",
                    title: "Toggle Fullscreen",
                    command: "fullscreen"
                ),
            ],
        ),
        .init(
            id: "workspaces",
            category: .common,
            title: "Workspaces",
            summary: "Use one modifier pattern for workspace numbers, then override specific workspaces only when needed.",
            actions: [],
        ),
        .init(
            id: "unmanaged",
            category: .unmanaged,
            title: "Unmanaged Windows",
            summary: "These only apply when Manage Windows is turned off.",
            actions: [
                shortcutAction(id: "snap-left-half", title: "Snap Left Half", command: "snap left-half"),
                shortcutAction(id: "snap-right-half", title: "Snap Right Half", command: "snap right-half"),
                shortcutAction(id: "snap-top-half", title: "Snap Top Half", command: "snap top-half"),
                shortcutAction(id: "snap-bottom-half", title: "Snap Bottom Half", command: "snap bottom-half"),
                shortcutAction(id: "snap-top-left", title: "Snap Top Left", command: "snap top-left"),
                shortcutAction(id: "snap-top-right", title: "Snap Top Right", command: "snap top-right"),
                shortcutAction(id: "snap-bottom-left", title: "Snap Bottom Left", command: "snap bottom-left"),
                shortcutAction(id: "snap-bottom-right", title: "Snap Bottom Right", command: "snap bottom-right"),
                shortcutAction(id: "snap-maximize", title: "Snap Maximize", command: "snap maximize"),
            ],
        ),
    ]
}

private func shortcutAction(
    id: String,
    title: String,
    subtitle: String? = nil,
    command: String,
) -> ShortcutSettingsModel.Action {
    let canonicalCommand = canonicalConfigCommandScript(command) ?? command
    return .init(
        id: id,
        title: title,
        subtitle: subtitle,
        commandScript: command,
        canonicalCommand: canonicalCommand,
    )
}

private let defaultWorkspaceSwitchModifiers: NSEvent.ModifierFlags = [.option]
private let defaultWorkspaceMoveModifiers: NSEvent.ModifierFlags = [.option, .shift]

struct WorkspaceShortcutState: Equatable {
    let switchModifiers: NSEvent.ModifierFlags
    let moveModifiers: NSEvent.ModifierFlags
    let switchOverrides: [String: String]
    let moveOverrides: [String: String]
}

func inferWorkspaceShortcutState(
    from entries: [String: String],
    workspaceNumbers: [String],
    defaultSwitchModifiers: NSEvent.ModifierFlags = defaultWorkspaceSwitchModifiers,
    defaultMoveModifiers: NSEvent.ModifierFlags = defaultWorkspaceMoveModifiers,
) -> WorkspaceShortcutState {
    let switchCommands = Dictionary(uniqueKeysWithValues: workspaceNumbers.map { ($0, workspaceCommand($0, kind: .switchTo)) })
    let moveCommands = Dictionary(uniqueKeysWithValues: workspaceNumbers.map { ($0, workspaceCommand($0, kind: .moveTo)) })

    var actualSwitchNotations: [String: String] = [:]
    var actualMoveNotations: [String: String] = [:]
    var switchModifierFrequencies: [NSEvent.ModifierFlags.RawValue: Int] = [:]
    var moveModifierFrequencies: [NSEvent.ModifierFlags.RawValue: Int] = [:]

    for (notation, command) in entries {
        if let workspaceName = switchCommands.first(where: { $0.value == command })?.key {
            actualSwitchNotations[workspaceName] = notation
            if let modifiers = matchingWorkspacePatternModifiers(notation: notation, workspaceName: workspaceName) {
                switchModifierFrequencies[modifiers.rawValue, default: 0] += 1
            }
        }
        if let workspaceName = moveCommands.first(where: { $0.value == command })?.key {
            actualMoveNotations[workspaceName] = notation
            if let modifiers = matchingWorkspacePatternModifiers(notation: notation, workspaceName: workspaceName) {
                moveModifierFrequencies[modifiers.rawValue, default: 0] += 1
            }
        }
    }

    let switchModifiers = NSEvent.ModifierFlags(
        rawValue: switchModifierFrequencies.max(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        })?.key ?? defaultSwitchModifiers.rawValue
    )
    let moveModifiers = NSEvent.ModifierFlags(
        rawValue: moveModifierFrequencies.max(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        })?.key ?? defaultMoveModifiers.rawValue
    )

    let switchOverrides = workspaceNumbers.reduce(into: [String: String]()) { result, workspaceName in
        guard let actualNotation = actualSwitchNotations[workspaceName],
              actualNotation != workspacePatternNotation(modifiers: switchModifiers, workspaceName: workspaceName)
        else { return }
        result[workspaceName] = actualNotation
    }
    let moveOverrides = workspaceNumbers.reduce(into: [String: String]()) { result, workspaceName in
        guard let actualNotation = actualMoveNotations[workspaceName],
              actualNotation != workspacePatternNotation(modifiers: moveModifiers, workspaceName: workspaceName)
        else { return }
        result[workspaceName] = actualNotation
    }

    return WorkspaceShortcutState(
        switchModifiers: switchModifiers,
        moveModifiers: moveModifiers,
        switchOverrides: switchOverrides,
        moveOverrides: moveOverrides,
    )
}

@MainActor
private func shortcutSettingsWorkspaceNumbers() -> [String] {
    let configuredNumbers = Set(Array(config.persistentWorkspaces).filter { workspaceKey(for: $0) != nil })
        .union(TrayMenuModel.shared.workspaces.map(\.name).filter { workspaceKey(for: $0) != nil })
    let defaults = (1 ... 9).map(String.init)
    let merged = configuredNumbers.union(defaults)
    return merged.sorted { lhs, rhs in
        guard let lhsInt = Int(lhs), let rhsInt = Int(rhs) else {
            return lhs < rhs
        }
        return lhsInt < rhsInt
    }
}

private func workspaceCommand(_ workspaceName: String, kind: ShortcutSettingsModel.WorkspaceShortcutKind) -> String {
    switch kind {
        case .switchTo:
            "workspace \(quoteCommandArgument(workspaceName))"
        case .moveTo:
            "move-node-to-workspace \(quoteCommandArgument(workspaceName))"
    }
}

private func parseWorkspaceCommandTarget(
    _ command: String,
    kind: ShortcutSettingsModel.WorkspaceShortcutKind
) -> String? {
    let prefix: String = switch kind {
        case .switchTo: "workspace "
        case .moveTo: "move-node-to-workspace "
    }
    guard command.hasPrefix(prefix) else { return nil }
    return String(command.dropFirst(prefix.count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
}

private func matchingWorkspacePatternModifiers(notation: String, workspaceName: String) -> NSEvent.ModifierFlags? {
    guard let key = workspaceKey(for: workspaceName),
          let (modifiers, actualKey) = try? parseBinding(notation, .emptyRoot, keyNotationToKeyCode).get(),
          actualKey == key
    else {
        return nil
    }
    return modifiers
}

private func workspacePatternNotation(modifiers: NSEvent.ModifierFlags, workspaceName: String) -> String? {
    guard let key = workspaceKey(for: workspaceName) else { return nil }
    return renderBindingNotation(modifiers: modifiers, key: key)
}

private func workspaceKey(for workspaceName: String) -> Key? {
    switch workspaceName {
        case "0": .zero
        case "1": .one
        case "2": .two
        case "3": .three
        case "4": .four
        case "5": .five
        case "6": .six
        case "7": .seven
        case "8": .eight
        case "9": .nine
        default: nil
    }
}

private func quoteCommandArgument(_ raw: String) -> String {
    if raw.range(of: #"^[A-Za-z0-9._/-]+$"#, options: .regularExpression) != nil {
        return raw
    }
    let escaped = raw
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

func notation(from shortcut: MASShortcut) -> String? {
    guard let key = Key(carbonKeyCode: UInt32(shortcut.keyCode)) else { return nil }
    let modifiers = normalizedRecorderModifiers(from: shortcut.modifierFlags)
    return renderBindingNotation(modifiers: modifiers, key: key)
}

func masShortcut(from notation: String) -> MASShortcut? {
    guard let (modifiers, key) = try? parseBinding(notation, .emptyRoot, keyNotationToKeyCode).get() else {
        return nil
    }
    return MASShortcut(keyCode: Int(key.carbonKeyCode), modifierFlags: modifiers)
}

private func normalizedRecorderModifiers(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    var result: NSEvent.ModifierFlags = []
    if flags.contains(.option) { result.insert(.option) }
    if flags.contains(.control) { result.insert(.control) }
    if flags.contains(.command) { result.insert(.command) }
    if flags.contains(.shift) { result.insert(.shift) }
    return result
}

func renderBindingNotation(modifiers: NSEvent.ModifierFlags, key: Key) -> String {
    modifiers.isEmpty ? key.toString() : "\(modifiers.toString())-\(key.toString())"
}

func displayBindingNotation(_ notation: String) -> String {
    notation.split(separator: "-").map { component in
        switch component {
            case "alt": "⌥"
            case "ctrl": "⌃"
            case "cmd": "⌘"
            case "shift": "⇧"
            case "left": "←"
            case "right": "→"
            case "up": "↑"
            case "down": "↓"
            case "enter": "↩"
            case "esc": "⎋"
            case "space": "Space"
            case "tab": "⇥"
            case "backspace": "⌫"
            case "semicolon": ";"
            case "comma": ","
            case "period": "."
            case "slash": "/"
            case "minus": "-"
            case "equal": "="
            default:
                String(component).uppercased()
        }
    }.joined(separator: "")
}

private extension Result {
    func get() throws -> Success {
        switch self {
            case .success(let value): value
            case .failure(let error): throw error
        }
    }
}

private func shortcutSettingsError(_ message: String) -> NSError {
    NSError(domain: winMuxAppId, code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
