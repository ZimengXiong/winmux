import Common
import TOMLKit

extension ParserProtocol {
    func transformRawConfig(
        _ raw: S,
        _ value: TOMLValueConvertible,
        _ backtrace: TomlBacktrace,
        _ errors: inout [TomlParseError],
    ) -> S {
        if let value = parse(value, backtrace, &errors).getOrNil(appendErrorTo: &errors) {
            return raw.copy(keyPath, value)
        }
        return raw
    }
}

protocol ParserProtocol<S>: Sendable {
    associatedtype T
    associatedtype S where S: ConvenienceCopyable
    var keyPath: SendableWritableKeyPath<S, T> { get }
    var parse: @Sendable (TOMLValueConvertible, TomlBacktrace, inout [TomlParseError]) -> ParsedToml<T> { get }
}

struct Parser<S: ConvenienceCopyable, T>: ParserProtocol {
    let keyPath: SendableWritableKeyPath<S, T>
    let parse: @Sendable (TOMLValueConvertible, TomlBacktrace, inout [TomlParseError]) -> ParsedToml<T>

    init(
        _ keyPath: SendableWritableKeyPath<S, T>,
        _ parse: @escaping @Sendable (TOMLValueConvertible, TomlBacktrace, inout [TomlParseError]) -> T,
    ) {
        self.keyPath = keyPath
        self.parse = { raw, backtrace, errors -> ParsedToml<T> in .success(parse(raw, backtrace, &errors)) }
    }

    init(
        _ keyPath: SendableWritableKeyPath<S, T>,
        _ parse: @escaping @Sendable (TOMLValueConvertible, TomlBacktrace) -> ParsedToml<T>,
    ) {
        self.keyPath = keyPath
        self.parse = { raw, backtrace, _ -> ParsedToml<T> in parse(raw, backtrace) }
    }
}
