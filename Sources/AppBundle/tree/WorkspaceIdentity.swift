import AppKit

struct WorkspaceId: RawRepresentable, Hashable, Identifiable, Sendable, Codable, CustomStringConvertible, Comparable {
    let rawValue: String

    var id: String { rawValue }
    var description: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static func < (lhs: WorkspaceId, rhs: WorkspaceId) -> Bool {
        lhs.rawValue.localizedStandardCompare(rhs.rawValue) == .orderedAscending
    }
}

struct WorkspaceProjectId: RawRepresentable, Hashable, Identifiable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible, Comparable {
    static let defaultProject = WorkspaceProjectId(rawValue: "default")

    let rawValue: String

    var id: String { rawValue }
    var description: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }

    func hasPrefix(_ prefix: String) -> Bool {
        rawValue.hasPrefix(prefix)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func < (lhs: WorkspaceProjectId, rhs: WorkspaceProjectId) -> Bool {
        lhs.rawValue.localizedStandardCompare(rhs.rawValue) == .orderedAscending
    }
}

struct DisplayLaneId: Hashable, Sendable, Codable, CustomStringConvertible {
    let topLeftCorner: CGPoint

    var description: String {
        "\(topLeftCorner.x),\(topLeftCorner.y)"
    }

    init(topLeftCorner: CGPoint) {
        self.topLeftCorner = topLeftCorner
    }

    @MainActor
    init(_ monitor: Monitor) {
        self.topLeftCorner = monitor.rect.topLeftCorner
    }
}

typealias MonitorKey = DisplayLaneId

struct WorkspaceScope: Hashable, Sendable {
    let projectId: WorkspaceProjectId
    let laneId: DisplayLaneId

    var monitor: DisplayLaneId { laneId }

    init(projectId: WorkspaceProjectId, laneId: DisplayLaneId) {
        self.projectId = projectId
        self.laneId = laneId
    }

    init(projectId: WorkspaceProjectId, monitor: DisplayLaneId) {
        self.init(projectId: projectId, laneId: monitor)
    }
}

enum WorkspaceLifecycle: String, Codable, Sendable {
    case durable
    case transient
    case archived
}
