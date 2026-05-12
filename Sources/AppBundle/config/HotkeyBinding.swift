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
@MainActor private var sequenceBindingsByPrefix: [Key: [SequenceBinding]] = [:]
@MainActor var sequenceBindingsPrefixKeys: Set<Key> = []
/// Timestamp of the last Escape press, used for sequence detection via local monitor
@MainActor private var lastSequencePrefixTime: DispatchTime? = nil
/// Which prefix key was pressed last
@MainActor private var lastSequencePrefixKey: Key? = nil
private let tapBindingTriggerDelayNs: UInt64 = 75_000_000
/// Max time (ns) between prefix key and subsequent key for a sequence binding
private let sequenceChordTimeoutNs: UInt64 = 300_000_000 // 300ms

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
    sequenceBindingsByPrefix = [:]
    sequenceBindingsPrefixKeys = []
    lastSequencePrefixTime = nil
    lastSequencePrefixKey = nil
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
    let mode = targetMode.flatMap { config.modes[$0] }
    let targetBindings = mode?.bindings ?? [:]
    activeTapBindings = mode?
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
    // Populate sequence binding lookup tables
    sequenceBindingsByPrefix = [:]
    sequenceBindingsPrefixKeys = []
    lastSequencePrefixTime = nil
    lastSequencePrefixKey = nil
    if let seqBindings = mode?.sequenceBindings.values {
        for seq in seqBindings {
            sequenceBindingsByPrefix[seq.prefix, default: []].append(seq)
            sequenceBindingsPrefixKeys.insert(seq.prefix)
        }
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

/// Called from the local keyDown monitor when the Escape key (or other prefix key)
/// is pressed. Records the timestamp so a subsequent matching key can trigger a
/// sequence binding. Does NOT consume the event.
@MainActor func noteSequencePrefixKeyPressed(_ prefix: Key) {
    lastSequencePrefixTime = DispatchTime.now()
    lastSequencePrefixKey = prefix
}

/// Called from the local keyDown monitor for every keyDown event.
/// If a prefix key was pressed recently (within `sequenceChordTimeoutNs`),
/// checks if this key matches a sequence binding and executes it.
/// Returns true if the event was consumed (should not reach the app).
@MainActor func handleSequenceKeyDown(event: NSEvent) -> Bool {
    guard let prefix = lastSequencePrefixKey,
          let lastTime = lastSequencePrefixTime,
          let bindings = sequenceBindingsByPrefix[prefix] else {
        return false
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - lastTime.uptimeNanoseconds
    guard elapsed < sequenceChordTimeoutNs else {
        // Timeout expired, clear state
        lastSequencePrefixTime = nil
        lastSequencePrefixKey = nil
        return false
    }
    // Check if this key matches any sequence binding for this prefix
    for seq in bindings {
        if seq.key.carbonKeyCode == event.keyCode {
            // Match! Execute the command and consume the event
            lastSequencePrefixTime = nil
            lastSequencePrefixKey = nil
            triggerBinding(seq.descriptionWithKeyNotation, seq.commands)
            return true
        }
    }
    // No match - clear state and let event pass through
    lastSequencePrefixTime = nil
    lastSequencePrefixKey = nil
    return false
}

@MainActor func noteTapBindingKeyDown() {
    if hotkeysSuspended { return }
    cancelPendingTapTriggers()
    pendingTapBindings = [:]
}

@MainActor func noteTapBindingFlagsChanged(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
    if hotkeysSuspended { return }
    if activeTapBindings.isEmpty && pendingTapBindings.isEmpty && pendingTapTriggerTasks.isEmpty { return }
    guard let tapModifier = TapModifierKey(keyCode: keyCode) else { return }
    cancelPendingTapTriggers()

    // Rebuild the pressed-modifier state from the event snapshot instead of only
    // applying the single changed key. macOS can occasionally drop a modifier
    // release event; if that happens, a stale entry here makes later single-key
    // tap launchers look like multi-modifier chords and they stop firing.
    pressedTapModifiers = tapModifiersPressed(in: modifierFlags)

    if pressedTapModifiers.contains(tapModifier) {
        let hadOtherPressedModifiers = !pressedTapModifiers.subtracting([tapModifier]).isEmpty
        pendingTapBindings = [:]
        if !hadOtherPressedModifiers, let binding = activeTapBindings[tapModifier] {
            pendingTapBindings[tapModifier] = binding
        }
        return
    }

    if let binding = pendingTapBindings.removeValue(forKey: tapModifier) {
        scheduleTapBindingTrigger(binding)
    }
}

private func tapModifiersPressed(in modifierFlags: NSEvent.ModifierFlags) -> Set<TapModifierKey> {
    Set(TapModifierKey.allCases.filter { $0.isPressed(in: modifierFlags) })
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

@MainActor func tapBindingPressedModifiersForTests() -> Set<TapModifierKey> {
    pressedTapModifiers
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
            lhs.commands.count == rhs.commands.count &&
            zip(lhs.commands, rhs.commands).allSatisfy { $0.equals($1) }
    }
}



/// Returns true if the binding string looks like a sequence (e.g. `esc-h`)
/// where the first segment before `-` is a known key, not a modifier.
private func looksLikeSequenceBinding(_ raw: String, _ mapping: [String: Key]) -> Bool {
    let rawKeys = raw.split(separator: "-")
    guard rawKeys.count == 2 else { return false }
    let first = String(rawKeys[0])
    // If the first part is a modifier, this is a chord, not a sequence
    guard modifiersMap[first] == nil else { return false }
    // If the first part is a known key name, treat as sequence
    return mapping[first] != nil
}

func parseBindings(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError], _ mapping: [String: Key]) -> (chordBindings: [String: HotkeyBinding], sequenceBindings: [String: SequenceBinding]) {
    guard let rawTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return ([:], [:])
    }
    var chordResult: [String: HotkeyBinding] = [:]
    var seqResult: [String: SequenceBinding] = [:]
    for (binding, rawCommand): (String, TOMLValueConvertible) in rawTable {
        let backtrace = backtrace + .key(binding)
        // Detect if this looks like a sequence binding (e.g. `esc-h`)
        // Parse as sequence if the first segment is not a modifier but is a known key
        if looksLikeSequenceBinding(binding, mapping) {
            let parsedPrefix = tryParseSequenceBinding(binding, backtrace, mapping)
            if parsedPrefix.isSuccess {
                let seqBindingResult: ParsedToml<SequenceBinding> = parsedPrefix.flatMap { (prefix, key) in
                    parseCommandOrCommands(rawCommand).toParsedToml(backtrace).map { cmds in
                        SequenceBinding(prefix: prefix, key: key, commands: cmds, descriptionWithKeyNotation: binding)
                    }
                }
                if let seqBinding = seqBindingResult.getOrNil(appendErrorTo: &errors) {
                    if seqResult.keys.contains(seqBinding.descriptionWithKeyNotation) {
                        errors.append(.semantic(backtrace, "'\(seqBinding.descriptionWithKeyNotation)' Sequence binding redeclaration"))
                    }
                    seqResult[seqBinding.descriptionWithKeyNotation] = seqBinding
                    continue
                }
            }
        }
        // Parse as chord binding (original logic)
        let parsed: ParsedToml<HotkeyBinding> = parseBinding(binding, backtrace, mapping).flatMap { modifiers, key in
            parseCommandOrCommands(rawCommand).toParsedToml(backtrace).map {
                HotkeyBinding(modifiers, key, $0, descriptionWithKeyNotation: binding)
            }
        }
        if let chord = parsed.getOrNil(appendErrorTo: &errors) {
            if chordResult.keys.contains(chord.descriptionWithKeyCode) {
                errors.append(.semantic(backtrace, "'\(chord.descriptionWithKeyCode)' Binding redeclaration"))
            }
            chordResult[chord.descriptionWithKeyCode] = chord
        }
    }
    return (chordResult, seqResult)
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
