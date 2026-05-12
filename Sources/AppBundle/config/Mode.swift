import Common
import HotKey
import TOMLKit

struct Mode: ConvenienceCopyable, Equatable, Sendable {
    var bindings: [String: HotkeyBinding]
    var tapBindings: [String: TapBinding]
    var sequenceBindings: [String: SequenceBinding]

    static let zero = Mode(bindings: [:], tapBindings: [:], sequenceBindings: [:])
}

func parseModes(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError], _ mapping: [String: Key]) -> [String: Mode] {
    guard let rawTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return [:]
    }
    var result: [String: Mode] = [:]
    for (key, value) in rawTable {
        result[key] = parseMode(value, backtrace + .key(key), &errors, mapping)
    }
    return result
}

func parseMode(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError], _ mapping: [String: Key]) -> Mode {
    guard let rawTable: TOMLTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return .zero
    }

    var result: Mode = .zero
    for (key, value) in rawTable {
        let backtrace = backtrace + .key(key)
        switch key {
            case "binding":
                let (chordBindings, seqBindings) = parseBindings(value, backtrace, &errors, mapping)
                result.bindings = chordBindings
                result.sequenceBindings = seqBindings
            case "binding-tap":
                result.tapBindings = parseTapBindings(value, backtrace, &errors)
            default:
                errors += [unknownKeyError(backtrace)]
        }
    }
    return result
}
