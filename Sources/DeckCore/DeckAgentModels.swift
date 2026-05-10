import Foundation

public struct DeckAgentSnapshot: Codable, Equatable, Sendable {
    public let worldId: String?
    public let inventory: DeckAgentInventory

    enum CodingKeys: String, CodingKey {
        case worldId
        case inventory
    }
}

public struct DeckAgentInventory: Codable, Equatable, Sendable {
    public let windows: [DeckAgentWindow]
    public let tabGroups: [DeckAgentTabGroup]
    public let workspaces: [DeckAgentWorkspace]
}

public struct DeckAgentWindow: Codable, Equatable, Sendable {
    public let windowId: UInt32
    public let title: String
    public let appName: String?
    public let appBundleId: String?
    public let workspace: String?
    public let tabGroupId: String?
}

public struct DeckAgentTabGroup: Codable, Equatable, Sendable {
    public let tabGroupId: String
    public let workspace: String?
    public let tabs: [UInt32]
}

public struct DeckAgentWorkspace: Codable, Equatable, Sendable {
    public let name: String
}

struct DeckAgentApplyRequest: Encodable {
    let schemaVersion: Int
    let worldId: String?
    let edit: DeckAgentEdit
}

struct DeckAgentEdit: Encodable {
    let operations: [DeckAgentOperation]
}

enum DeckAgentOperation: Encodable, Equatable {
    case moveWindowToWorkspace(windowId: UInt32, workspace: String, focus: Bool)
    case createTabGroup(tabGroupId: String?, workspace: String?, tabs: [UInt32], activeWindowId: UInt32?)

    enum CodingKeys: String, CodingKey {
        case type
        case windowId
        case workspace
        case focus
        case tabGroupId
        case tabs
        case activeWindowId
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .moveWindowToWorkspace(let windowId, let workspace, let focus):
                try container.encode("moveWindowToWorkspace", forKey: .type)
                try container.encode(windowId, forKey: .windowId)
                try container.encode(workspace, forKey: .workspace)
                try container.encode(focus, forKey: .focus)
            case .createTabGroup(let tabGroupId, let workspace, let tabs, let activeWindowId):
                try container.encode("createTabGroup", forKey: .type)
                try container.encodeIfPresent(tabGroupId, forKey: .tabGroupId)
                try container.encodeIfPresent(workspace, forKey: .workspace)
                try container.encode(tabs, forKey: .tabs)
                try container.encodeIfPresent(activeWindowId, forKey: .activeWindowId)
        }
    }
}
