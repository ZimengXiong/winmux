public enum TabNextPrev: String, CaseIterable, Equatable, Sendable {
    case tabNext = "tab-next"
    case tabPrev = "tab-prev"

    public var focusOffset: Int {
        switch self {
            case .tabNext: 1
            case .tabPrev: -1
        }
    }
}

public enum FocusTargetArg: Equatable, Sendable {
    case direction(CardinalDirection)
    case dfsRelative(DfsNextPrev)
    case tabRelative(TabNextPrev)
}

extension FocusTargetArg: CaseIterable {
    public static var allCases: [FocusTargetArg] {
        CardinalDirection.allCases.map { .direction($0) } +
            DfsNextPrev.allCases.map { .dfsRelative($0) } +
            TabNextPrev.allCases.map { .tabRelative($0) }
    }
}

extension FocusTargetArg: RawRepresentable {
    public typealias RawValue = String

    public init?(rawValue: RawValue) {
        if let direction = CardinalDirection(rawValue: rawValue) {
            self = .direction(direction)
        } else if let nextPrev = DfsNextPrev(rawValue: rawValue) {
            self = .dfsRelative(nextPrev)
        } else if let nextPrev = TabNextPrev(rawValue: rawValue) {
            self = .tabRelative(nextPrev)
        } else {
            return nil
        }
    }

    public var rawValue: RawValue {
        switch self {
            case .direction(let direction): direction.rawValue
            case .dfsRelative(let nextPrev): nextPrev.rawValue
            case .tabRelative(let nextPrev): nextPrev.rawValue
        }
    }
}
