import Common

enum AgentLayoutDirection: String, Codable {
    case horizontal
    case vertical

    var orientation: Orientation { self == .horizontal ? .h : .v }
}
