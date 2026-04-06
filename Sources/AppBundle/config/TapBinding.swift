import AppKit
import Common
import TOMLKit

enum TapModifierKey: String, CaseIterable, Equatable, Sendable {
    case leftAlt = "left-alt"
    case rightAlt = "right-alt"
    case leftCmd = "left-cmd"
    case rightCmd = "right-cmd"
    case leftCtrl = "left-ctrl"
    case rightCtrl = "right-ctrl"
    case leftShift = "left-shift"
    case rightShift = "right-shift"

    init?(keyCode: UInt16) {
        switch keyCode {
            case 58: self = .leftAlt
            case 61: self = .rightAlt
            case 55: self = .leftCmd
            case 54: self = .rightCmd
            case 59: self = .leftCtrl
            case 62: self = .rightCtrl
            case 56: self = .leftShift
            case 60: self = .rightShift
            default: return nil
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
            case .leftAlt, .rightAlt: .option
            case .leftCmd, .rightCmd: .command
            case .leftCtrl, .rightCtrl: .control
            case .leftShift, .rightShift: .shift
        }
    }
}

struct TapBinding: Equatable, Sendable {
    let trigger: TapModifierKey
    let commands: [any Command]
    let descriptionWithKeyNotation: String

    init(_ trigger: TapModifierKey, _ commands: [any Command], descriptionWithKeyNotation: String? = nil) {
        self.trigger = trigger
        self.commands = commands
        self.descriptionWithKeyNotation = descriptionWithKeyNotation ?? trigger.rawValue
    }

    static func == (lhs: TapBinding, rhs: TapBinding) -> Bool {
        lhs.trigger == rhs.trigger &&
            lhs.descriptionWithKeyNotation == rhs.descriptionWithKeyNotation &&
            zip(lhs.commands, rhs.commands).allSatisfy { $0.equals($1) }
    }
}

func parseTapBindings(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> [String: TapBinding] {
    guard let rawTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return [:]
    }
    var result: [String: TapBinding] = [:]
    for (binding, rawCommand): (String, TOMLValueConvertible) in rawTable {
        let backtrace = backtrace + .key(binding)
        let tapKey = TapModifierKey(rawValue: binding)
            .orFailure(.semantic(
                backtrace,
                "Unsupported tap binding key '\(binding)'. Supported keys: \(TapModifierKey.allCases.map(\.rawValue).joined(separator: ", "))",
            ))
            .flatMap { tapKey -> ParsedToml<TapBinding> in
                parseCommandOrCommands(rawCommand).toParsedToml(backtrace).map {
                    TapBinding(tapKey, $0, descriptionWithKeyNotation: binding)
                }
            }
            .getOrNil(appendErrorTo: &errors)
        if let tapKey {
            result[tapKey.descriptionWithKeyNotation] = tapKey
        }
    }
    return result
}
