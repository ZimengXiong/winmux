import TOMLKit

enum TomlParseError: Error, CustomStringConvertible, Equatable {
    case semantic(_ backtrace: TomlBacktrace, _ message: String)
    case syntax(_ message: String)

    var description: String {
        return switch self {
            case .semantic(let backtrace, let message) where backtrace.description.isEmpty: message
            case .semantic(let backtrace, let message): "\(backtrace): \(message)"
            case .syntax(let message): message
        }
    }
}

typealias ParsedToml<T> = Result<T, TomlParseError>

func unknownKeyError(_ backtrace: TomlBacktrace) -> TomlParseError {
    .semantic(backtrace, backtrace.isRootKey ? "Unknown top-level key" : "Unknown key")
}

func expectedActualTypeError(expected: TOMLType, actual: TOMLType, _ backtrace: TomlBacktrace) -> TomlParseError {
    .semantic(backtrace, expectedActualTypeError(expected: expected, actual: actual))
}

func expectedActualTypeError(expected: [TOMLType], actual: TOMLType, _ backtrace: TomlBacktrace) -> TomlParseError {
    .semantic(backtrace, expectedActualTypeError(expected: expected, actual: actual))
}
