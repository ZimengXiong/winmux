import Common

enum AgentPaneRelationKind: String, Codable {
    case leftOf
    case rightOf
    case above
    case below

    var orientation: Orientation {
        switch self {
            case .leftOf, .rightOf: .h
            case .above, .below: .v
        }
    }

    var sourceIsAfterTarget: Bool {
        switch self {
            case .rightOf, .below: true
            case .leftOf, .above: false
        }
    }
}
