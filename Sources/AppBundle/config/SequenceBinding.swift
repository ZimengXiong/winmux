import AppKit
import Common
import HotKey
import TOMLKit

struct SequenceBinding: Equatable, Sendable {
    let prefix: Key
    let key: Key
    let commands: [any Command]
    let descriptionWithKeyNotation: String

    static func == (lhs: SequenceBinding, rhs: SequenceBinding) -> Bool {
        lhs.prefix == rhs.prefix &&
            lhs.key == rhs.key &&
            lhs.descriptionWithKeyNotation == rhs.descriptionWithKeyNotation &&
            lhs.commands.count == rhs.commands.count &&
            zip(lhs.commands, rhs.commands).allSatisfy { $0.equals($1) }
    }
}

/// Try to parse a binding as a sequence (e.g. `esc-h`).
/// Returns `.success` only if the first segment before `-` is NOT a modifier
/// but IS a known key name (like `esc`).
func tryParseSequenceBinding(
    _ raw: String,
    _ backtrace: TomlBacktrace,
    _ mapping: [String: Key]
) -> ParsedToml<(prefix: Key, key: Key)> {
    let rawKeys = raw.split(separator: "-")
    guard rawKeys.count == 2 else {
        return .failure(.semantic(backtrace, "Sequence bindings require exactly two keys separated by '-'"))
    }

    let prefixName = String(rawKeys[0])
    let keyName = String(rawKeys[1])

    // If the first part is a known modifier, this is a chord binding, not a sequence
    if modifiersMap[prefixName] != nil {
        return .failure(.semantic(backtrace, "'\(raw)' is a chord binding, not a sequence"))
    }

    guard let prefix = mapping[prefixName] else {
        return .failure(.semantic(backtrace, "Can't parse the prefix key '\(prefixName)' in '\(raw)' binding"))
    }

    guard let key = mapping[keyName] else {
        return .failure(.semantic(backtrace, "Can't parse the key '\(keyName)' in '\(raw)' binding"))
    }

    return .success((prefix, key))
}
