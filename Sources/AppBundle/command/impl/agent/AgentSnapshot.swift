import AppKit
import Common
import Foundation

// MARK: - Query

let agentSnapshotQueryMaxAttempts = 2

@MainActor
private var agentSnapshotAfterMembershipCaptureForTests: (@MainActor @Sendable (Int) async -> Void)?

@MainActor
func setAgentSnapshotAfterMembershipCaptureForTests(
    _ hook: (@MainActor @Sendable (Int) async -> Void)?
) {
    agentSnapshotAfterMembershipCaptureForTests = hook
}

enum AgentSnapshotQueryError: LocalizedError {
    case worldKeptChanging(attempts: Int)

    var errorDescription: String? {
        switch self {
            case .worldKeptChanging(let attempts):
                "Window state kept changing while WinMux built the agent snapshot after \(attempts) attempts. Retry 'winmux agent query' after window movement settles."
        }
    }
}

struct AgentSnapshot: Encodable {
    let schemaVersion: Int
    let snapshotId: String
    let worldId: String
    let inventory: AgentInventory
    let reasoning: AgentReasoning
    let edit: AgentEditTemplate

    @MainActor
    static func query() async throws -> AgentSnapshot {
        for attempt in 1 ... agentSnapshotQueryMaxAttempts {
            let worldId = currentAgentWorldId()
            let capture = AgentSnapshotCapture()
            if let hook = agentSnapshotAfterMembershipCaptureForTests {
                await hook(attempt)
            }

            do {
                let snapshot = try await capture.makeSnapshot(worldId: worldId)
                if currentAgentWorldId() == worldId {
                    return snapshot
                }
            } catch {
                if currentAgentWorldId() == worldId {
                    throw error
                }
            }
        }
        throw AgentSnapshotQueryError.worldKeptChanging(attempts: agentSnapshotQueryMaxAttempts)
    }
}

@MainActor
private struct AgentSnapshotCapture {
    let windows: [Window]
    let tabGroups: [TilingContainer]
    let workspaceInfos: [AgentWorkspaceInfo]
    let panes: [AgentPaneInfo]
    let relations: [AgentPaneRelation]
    let rawTrees: [AgentRawWorkspaceTree]

    init() {
        let workspaces = userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace)
        var windowNodes: [Window] = []
        var tabGroupNodes: [TilingContainer] = []
        var workspaceInfos: [AgentWorkspaceInfo] = []
        var allPanes: [AgentPaneInfo] = []
        var allRelations: [AgentPaneRelation] = []
        var rawTrees: [AgentRawWorkspaceTree] = []

        for workspace in workspaces {
            let panes = workspace.agentPaneInfos()
            let relations = workspace.agentPaneRelations()
            allPanes.append(contentsOf: panes)
            allRelations.append(contentsOf: relations)
            rawTrees.append(AgentRawWorkspaceTree(workspace: workspace.name, tree: workspace.rootTilingContainer.agentRawLayoutNode()))
            workspaceInfos.append(AgentWorkspaceInfo(
                name: workspace.name,
                displayName: workspaceDisplayName(workspace.name),
                visible: workspace.isVisible,
                focused: focus.workspace == workspace,
                monitorId: workspace.workspaceMonitor.monitorId_oneBased,
                panes: panes.map(\.paneId),
            ))
            tabGroupNodes.append(contentsOf: workspace.rootTilingContainer.allAgentTabGroupsRecursive)
            windowNodes.append(contentsOf: workspace.allLeafWindowsRecursive)
        }
        windowNodes.append(contentsOf: macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self))

        var seenWindowIds: Set<UInt32> = []
        windows = windowNodes.filter { seenWindowIds.insert($0.windowId).inserted }
        tabGroups = tabGroupNodes
        self.workspaceInfos = workspaceInfos
        panes = allPanes
        relations = allRelations
        self.rawTrees = rawTrees
    }

    func makeSnapshot(worldId: String) async throws -> AgentSnapshot {
        var windowInfos: [AgentWindowInfo] = []
        for window in windows {
            windowInfos.append(try await AgentWindowInfo(window))
        }
        var tabGroupInfos: [AgentTabGroupInfo] = []
        for group in tabGroups {
            tabGroupInfos.append(await AgentTabGroupInfo(group))
        }

        let inventory = AgentInventory(
            windows: windowInfos.sortedBy(\.windowId),
            tabGroups: tabGroupInfos.sortedBy(\.tabGroupId),
            workspaces: workspaceInfos.sortedBy(\.name),
        )
        let reasoning = AgentReasoning(
            panes: panes.sortedBy(\.paneId),
            relations: relations.sortedBy([{ $0.workspace }, { $0.paneId }]),
            rawTrees: rawTrees.sortedBy(\.workspace),
        )
        return AgentSnapshot(
            schemaVersion: supportedAgentSchemaVersion,
            snapshotId: ISO8601DateFormatter().string(from: Date()),
            worldId: worldId,
            inventory: inventory,
            reasoning: reasoning,
            edit: AgentEditTemplate(operations: [], layout: nil),
        )
    }
}

struct AgentInventory: Encodable {
    let windows: [AgentWindowInfo]
    let tabGroups: [AgentTabGroupInfo]
    let workspaces: [AgentWorkspaceInfo]
}

struct AgentWorkspaceInfo: Encodable {
    let name: String
    let displayName: String
    let visible: Bool
    let focused: Bool
    let monitorId: Int?
    let panes: [String]
}

struct AgentWindowInfo: Encodable {
    let windowId: UInt32
    let title: String
    let appName: String?
    let appBundleId: String?
    let pid: Int32
    let workspace: String?
    let paneId: String?
    let tabGroupId: String?
    let focused: Bool
    let winMuxFullscreen: Bool
    let noOuterGapsInFullscreen: Bool
    let layout: String
    let size: CGFloat?
    let sizeAxis: AgentLayoutDirection?
    let frame: AgentRect?

    @MainActor
    init(_ window: Window) async throws {
        windowId = window.windowId
        title = try await window.title
        appName = window.app.name
        appBundleId = window.app.rawAppBundleId
        pid = window.app.pid
        workspace = window.agentInventoryWorkspaceName
        tabGroupId = window.nearestWindowTabGroup.map(agentTabGroupId)
        paneId = window.agentPaneId
        focused = focus.windowOrNil == window
        winMuxFullscreen = window.isFullscreen
        noOuterGapsInFullscreen = window.noOuterGapsInFullscreen
        layout = window.agentLayoutDescription
        let sizingNode = window.agentPaneSizingNode
        size = sizingNode.agentSizeRatio
        sizeAxis = sizingNode.agentSizeAxis
        // lastKnownActualRect is invalidated on move/resize events; fetch live when it's stale
        // so the reported frame reflects reality rather than the last cached observation.
        var actualRect = window.lastKnownActualRect
        if actualRect == nil {
            actualRect = try? await window.getAxRect()
        }
        frame = (actualRect ?? window.lastAppliedLayoutPhysicalRect ?? window.lastAppliedLayoutVirtualRect).map(AgentRect.init)
    }
}

private extension Window {
    @MainActor
    var agentInventoryWorkspaceName: String? {
        if let nodeWorkspace {
            return nodeWorkspace.name
        }
        return switch layoutReason {
            case .standard: nil
            case .macos(_, let previousWorkspaceName): previousWorkspaceName
        }
    }
}

struct AgentTabGroupInfo: Encodable {
    let tabGroupId: String
    let paneId: String
    let workspace: String?
    let activeWindowId: UInt32?
    let tabs: [UInt32]
    let tabTitles: [String]
    let size: CGFloat?
    let sizeAxis: AgentLayoutDirection?
    let frame: AgentRect?

    @MainActor
    init(_ group: TilingContainer) async {
        tabGroupId = agentTabGroupId(group)
        paneId = agentPaneIdForTabGroup(tabGroupId: tabGroupId)
        workspace = group.nodeWorkspace?.name
        activeWindowId = group.tabActiveWindow?.windowId
        let windows = group.agentTabWindows
        tabs = windows.map(\.windowId)
        var titles: [String] = []
        for window in windows {
            titles.append((try? await window.title) ?? "")
        }
        tabTitles = titles
        size = group.agentSizeRatio
        sizeAxis = group.agentSizeAxis
        frame = (group.lastAppliedLayoutPhysicalRect ?? group.lastAppliedLayoutVirtualRect).map(AgentRect.init)
    }
}

struct AgentReasoning: Encodable {
    let panes: [AgentPaneInfo]
    let relations: [AgentPaneRelation]
    let rawTrees: [AgentRawWorkspaceTree]
}

struct AgentPaneInfo: Encodable {
    let paneId: String
    let kind: AgentPaneKind
    let workspace: String
    let windowId: UInt32?
    let tabGroupId: String?
    let label: String
    let size: CGFloat?
    let sizeAxis: AgentLayoutDirection?
    let frame: AgentRect?
}

enum AgentPaneKind: String, Codable {
    case window
    case tabGroup
}

struct AgentPaneRelation: Encodable {
    let workspace: String
    let paneId: String
    var left: String?
    var right: String?
    var above: String?
    var below: String?
}

struct AgentRawWorkspaceTree: Encodable {
    let workspace: String
    let tree: AgentRawLayoutNode
}

indirect enum AgentRawLayoutNode: Encodable {
    case split(direction: AgentLayoutDirection, layout: String, size: CGFloat?, children: [AgentRawLayoutNode])
    case window(windowId: UInt32, size: CGFloat?)
    case tabGroup(tabGroupId: String, activeWindowId: UInt32?, tabs: [UInt32], size: CGFloat?)

    enum CodingKeys: String, CodingKey {
        case kind
        case direction
        case layout
        case size
        case children
        case windowId
        case tabGroupId
        case activeWindowId
        case tabs
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .split(let direction, let layout, let size, let children):
                try container.encode("split", forKey: .kind)
                try container.encode(direction, forKey: .direction)
                try container.encode(layout, forKey: .layout)
                try container.encodeIfPresent(size, forKey: .size)
                try container.encode(children, forKey: .children)
            case .window(let windowId, let size):
                try container.encode("window", forKey: .kind)
                try container.encode(windowId, forKey: .windowId)
                try container.encodeIfPresent(size, forKey: .size)
            case .tabGroup(let tabGroupId, let activeWindowId, let tabs, let size):
                try container.encode("tabGroup", forKey: .kind)
                try container.encode(tabGroupId, forKey: .tabGroupId)
                try container.encode(activeWindowId, forKey: .activeWindowId)
                try container.encode(tabs, forKey: .tabs)
                try container.encodeIfPresent(size, forKey: .size)
        }
    }
}

struct AgentRect: Codable, Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ rect: Rect) {
        x = rect.topLeftX
        y = rect.topLeftY
        width = rect.width
        height = rect.height
    }
}

struct AgentEditTemplate: Encodable {
    let operations: [String]
    let layout: AgentLayoutEdit?
}
