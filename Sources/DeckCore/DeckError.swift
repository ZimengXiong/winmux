import Foundation

public enum DeckError: Error, CustomStringConvertible, Equatable {
    case invalidArguments(String)
    case invalidProfile(String)
    case profileNotFound(String)
    case commandFailed(String)
    case winMuxUnavailable(String)

    public var description: String {
        return switch self {
            case .invalidArguments(let message),
                 .invalidProfile(let message),
                 .profileNotFound(let message),
                 .commandFailed(let message),
                 .winMuxUnavailable(let message):
                message
        }
    }
}
