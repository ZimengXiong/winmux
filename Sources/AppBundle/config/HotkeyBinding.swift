import AppKit
import Common
import Foundation
import HotKey
import TOMLKit

@MainActor private var hotkeys: [String: HotKey] = [:]
@MainActor private var activeTapBindings: [TapModifierKey: TapBinding] = [:]
@MainActor private var pendingTapBindings: [TapModifierKey: TapBinding] = [:]
@MainActor private var pressedTapModifiers: Set<TapModifierKey> = []
@MainActor private var pendingTapTriggerTasks: [TapModifierKey: Task<Void, Never>] = [:]
@MainActor private var pendingTapTriggerTokens: [TapModifierKey: Int] = [:]
@MainActor private var nextTapTriggerToken = 0
@MainActor private var hotkeysSuspended = false
private let tapBindingTriggerDelayNs: UInt64 = 75_000_000

@MainActor func resetHotKeys() {
    // Explicitly unregister all hotkeys. We cannot always rely on destruction of the HotKey object to trigger
    // unregistration because we might be running inside a hotkey handler that is keeping its HotKey object alive.
    for (_, key) in hotkeys {
        key.isEnabled = false
    }
    hotkeys = [:]
    activeTapBindings = [:]
    pendingTapBindings = [:]
    pressedTapModifiers = []
    cancelPendingTapTriggers()
    hotkeysSuspended = false
}

extension HotKey {
    var isEnabled: Bool {
        get { !isPaused }
        set {
            if isEnabled != newValue {
                isPaused = !newValue
            }
        }
    }
}

@MainActor var activeMode: String? = mainModeId
@MainActor func setHotkeysSuspended(_ suspended: Bool) {
    if hotkeysSuspended == suspended { return }
    hotkeysSuspended = suspended
    if suspended {
        pendingTapBindings = [:]
        pressedTapModifiers = []
        cancelPendingTapTriggers()
    }
    applyHotkeyEnabledState()
}

@MainActor func activateMode(_ targetMode: String?) async throws {
    let targetBindings = targetMode.flatMap { config.modes[$0] }?.bindings ?? [:]
    activeTapBindings = targetMode
        .flatMap { config.modes[$0] }?
        .tapBindings
        .values
        .reduce(into: [:]) { $0[$1.trigger] = $1 } ?? [:]
    pendingTapBindings = [:]
    pressedTapModifiers = []
    cancelPendingTapTriggers()
    for binding in targetBindings.values where !hotkeys.keys.contains(binding.descriptionWithKeyCode) {
        hotkeys[binding.descriptionWithKeyCode] = HotKey(key: binding.keyCode, modifiers: binding.modifiers, keyDownHandler: {
            Task { @MainActor in
                if hotkeysSuspended { return }
                noteTapBindingKeyDown()
                triggerBinding(binding.descriptionWithKeyNotation, binding.commands)
            }
        })
    }
    let oldMode = activeMode
    activeMode = targetMode
    applyHotkeyEnabledState()
    if oldMode != targetMode {
        broadcastEvent(.modeChanged(mode: targetMode))
        if !config.onModeChanged.isEmpty {
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.onModeChanged, token) {
                _ = try await config.onModeChanged.runCmdSeq(.defaultEnv, .emptyStdin)
            }
        }
    }
}

@MainActor private func triggerBinding(_ binding: String, _ commands: [any Command]) {
    if hotkeysSuspended { return }
    Task {
        if let activeMode {
            broadcastEvent(.bindingTriggered(
                mode: activeMode,
                binding: binding,
            ))
            try await runLightSession(
                .hotkeyBinding,
                .checkServerIsEnabledOrDie(),
                shouldSchedulePostRefresh: !commands.canSkipPostCommandRefresh
            ) { () throws in
                _ = try await commands.runCmdSeq(.defaultEnv, .emptyStdin)
            }
        }
    }
}

@MainActor func noteTapBindingKeyDown() {
    if hotkeysSuspended { return }
    cancelPendingTapTriggers()
    pendingTapBindings = [:]
}

@MainActor func noteTapBindingFlagsChanged(keyCode: UInt16) {
    if hotkeysSuspended { return }
    if activeTapBindings.isEmpty && pendingTapBindings.isEmpty && pendingTapTriggerTasks.isEmpty { return }
    guard let tapModifier = TapModifierKey(keyCode: keyCode) else { return }
    cancelPendingTapTriggers()

    if pressedTapModifiers.contains(tapModifier) {
        pressedTapModifiers.remove(tapModifier)
        if let binding = pendingTapBindings.removeValue(forKey: tapModifier) {
            scheduleTapBindingTrigger(binding)
        }
        return
    }

    let hadOtherPressedModifiers = !pressedTapModifiers.isEmpty
    pressedTapModifiers.insert(tapModifier)
    pendingTapBindings = [:]
    if !hadOtherPressedModifiers, let binding = activeTapBindings[tapModifier] {
        pendingTapBindings[tapModifier] = binding
    }
}

@MainActor private func scheduleTapBindingTrigger(_ binding: TapBinding) {
    let trigger = binding.trigger
    nextTapTriggerToken += 1
    let token = nextTapTriggerToken
    pendingTapTriggerTokens[trigger] = token
    let task = Task { @MainActor in
        try? await Task.sleep(nanoseconds: tapBindingTriggerDelayNs)
        guard pendingTapTriggerTokens[trigger] == token else { return }
        pendingTapTriggerTasks[trigger] = nil
        pendingTapTriggerTokens[trigger] = nil
        guard pressedTapModifiers.isEmpty else { return }
        triggerBinding(binding.descriptionWithKeyNotation, binding.commands)
    }
    pendingTapTriggerTasks[trigger] = task
}

@MainActor private func cancelPendingTapTriggers() {
    for task in pendingTapTriggerTasks.values {
        task.cancel()
    }
    pendingTapTriggerTasks = [:]
    pendingTapTriggerTokens = [:]
}

@MainActor private func applyHotkeyEnabledState() {
    let targetBindings = activeMode.flatMap { config.modes[$0] }?.bindings ?? [:]
    for (binding, key) in hotkeys {
        key.isEnabled = !hotkeysSuspended && targetBindings.keys.contains(binding)
    }
}

struct HotkeyBinding: Equatable, Sendable {
    let modifiers: NSEvent.ModifierFlags
    let keyCode: Key
    let commands: [any Command]
    let descriptionWithKeyCode: String
    let descriptionWithKeyNotation: String

    init(_ modifiers: NSEvent.ModifierFlags, _ keyCode: Key, _ commands: [any Command], descriptionWithKeyNotation: String) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.commands = commands
        self.descriptionWithKeyCode = modifiers.isEmpty
            ? keyCode.toString()
            : modifiers.toString() + "-" + keyCode.toString()
        self.descriptionWithKeyNotation = descriptionWithKeyNotation
    }

    static func == (lhs: HotkeyBinding, rhs: HotkeyBinding) -> Bool {
        lhs.modifiers == rhs.modifiers &&
            lhs.keyCode == rhs.keyCode &&
            lhs.descriptionWithKeyCode == rhs.descriptionWithKeyCode &&
            zip(lhs.commands, rhs.commands).allSatisfy { $0.equals($1) }
    }
}

func parseBindings(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError], _ mapping: [String: Key]) -> [String: HotkeyBinding] {
    guard let rawTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return [:]
    }
    var result: [String: HotkeyBinding] = [:]
    for (binding, rawCommand): (String, TOMLValueConvertible) in rawTable {
        let backtrace = backtrace + .key(binding)
        let binding = parseBinding(binding, backtrace, mapping)
            .flatMap { modifiers, key -> ParsedToml<HotkeyBinding> in
                parseCommandOrCommands(rawCommand).toParsedToml(backtrace).map {
                    HotkeyBinding(modifiers, key, $0, descriptionWithKeyNotation: binding)
                }
            }
            .getOrNil(appendErrorTo: &errors)
        if let binding {
            if result.keys.contains(binding.descriptionWithKeyCode) {
                errors.append(.semantic(backtrace, "'\(binding.descriptionWithKeyCode)' Binding redeclaration"))
            }
            result[binding.descriptionWithKeyCode] = binding
        }
    }
    return result
}

func parseBinding(_ raw: String, _ backtrace: TomlBacktrace, _ mapping: [String: Key]) -> ParsedToml<(NSEvent.ModifierFlags, Key)> {
    let rawKeys = raw.split(separator: "-")
    let modifiers: ParsedToml<NSEvent.ModifierFlags> = rawKeys.dropLast()
        .mapAllOrFailure {
            modifiersMap[String($0)].orFailure(.semantic(backtrace, "Can't parse modifiers in '\(raw)' binding"))
        }
        .map { NSEvent.ModifierFlags($0) }
    let key: ParsedToml<Key> = rawKeys.last.flatMap { mapping[String($0)] }
        .orFailure(.semantic(backtrace, "Can't parse the key in '\(raw)' binding"))
    return modifiers.flatMap { modifiers -> ParsedToml<(NSEvent.ModifierFlags, Key)> in
        key.flatMap { key -> ParsedToml<(NSEvent.ModifierFlags, Key)> in
            .success((modifiers, key))
        }
    }
}
