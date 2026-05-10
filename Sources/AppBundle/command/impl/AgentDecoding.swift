import AppKit
import Common
import Foundation

struct AgentWindowTarget: Decodable {
    let windowId: UInt32?
    let match: AgentWindowMatch?

    @MainActor
    func resolveWindow() async throws -> Window? {
        if let windowId { return Window.get(byId: windowId) }
        guard let match else { return nil }
        for window in Workspace.all.flatMap(\.allLeafWindowsRecursive) {
            if try await match.matches(window) {
                return window
            }
        }
        return nil
    }
}

struct AgentWindowMatch: Decodable {
    let appName: String?
    let appBundleId: String?
    let titleContains: String?

    @MainActor
    func matches(_ window: Window) async throws -> Bool {
        if let appName, window.app.name != appName { return false }
        if let appBundleId, window.app.rawAppBundleId != appBundleId { return false }
        if let titleContains, try await !window.title.localizedCaseInsensitiveContains(titleContains) { return false }
        return true
    }
}

struct AgentPaneRef: Codable {
    let paneId: String?
    let windowId: UInt32?
    let tabGroupId: String?

    @MainActor
    func resolveNode(context: AgentApplyContext? = nil) -> TreeNode? {
        if let paneId {
            if paneId.hasPrefix("pane-tabgroup-") {
                return resolveAgentTabGroup(String(paneId.dropFirst("pane-".count)), context: context)
            }
            if paneId.hasPrefix("pane-"), let windowId = UInt32(paneId.dropFirst("pane-".count)) {
                return Window.get(byId: windowId)
            }
        }
        if let windowId { return Window.get(byId: windowId) }
        if let tabGroupId { return resolveAgentTabGroup(tabGroupId, context: context) }
        return nil
    }

    @MainActor
    func canResolve(in context: AgentValidationContext) -> Bool {
        if resolveNode() != nil { return true }
        if let tabGroupId, context.plannedTabGroups[tabGroupId] != nil { return true }
        if let paneId, paneId.hasPrefix("pane-tabgroup-") {
            return context.plannedTabGroups[String(paneId.dropFirst("pane-".count))] != nil
        }
        return false
    }
}

extension KeyedDecodingContainer where K == AgentOperation.CodingKeys {
    func decodeAgentPaneRef(primaryKey: K, paneIdKey: K, windowIdKey: K) throws -> AgentPaneRef {
        if contains(primaryKey) {
            return try decode(AgentPaneRef.self, forKey: primaryKey)
        }
        if let paneId = try decodeIfPresent(String.self, forKey: paneIdKey) {
            return AgentPaneRef(paneId: paneId, windowId: nil, tabGroupId: nil)
        }
        if let windowId = try decodeIfPresent(UInt32.self, forKey: windowIdKey) {
            return AgentPaneRef(paneId: nil, windowId: windowId, tabGroupId: nil)
        }
        return try decode(AgentPaneRef.self, forKey: primaryKey)
    }

    func decodeWindowIdArray(primaryKey: K, aliasKey: K) throws -> [UInt32] {
        if contains(primaryKey) {
            return try decode([UInt32].self, forKey: primaryKey)
        }
        return try decode([UInt32].self, forKey: aliasKey)
    }

    func decodeAgentSizeAxis(axisKey: K, directionKey: K) throws -> AgentLayoutDirection? {
        if let axis = try decodeIfPresent(AgentLayoutDirection.self, forKey: axisKey) {
            return axis
        }
        return try decodeIfPresent(AgentLayoutDirection.self, forKey: directionKey)
    }
}

extension KeyedDecodingContainer {
    func decodeAgentSizeRatio(sizeKey: K, percentKey: K) throws -> CGFloat {
        if let percent = try decodeIfPresent(CGFloat.self, forKey: percentKey) {
            return try normalizeAgentSizeRatio(percent, percentKey: percentKey)
        }
        return try normalizeAgentSizeRatio(try decode(CGFloat.self, forKey: sizeKey), percentKey: sizeKey)
    }

    func decodeAgentSizeRatioIfPresent(sizeKey: K, percentKey: K) throws -> CGFloat? {
        if let percent = try decodeIfPresent(CGFloat.self, forKey: percentKey) {
            return try normalizeAgentSizeRatio(percent, percentKey: percentKey)
        }
        guard let size = try decodeIfPresent(CGFloat.self, forKey: sizeKey) else { return nil }
        return try normalizeAgentSizeRatio(size, percentKey: sizeKey)
    }
}

func normalizedAgentOperationType(_ type: String) -> String {
    type.filter { $0 != "_" && $0 != "-" }.lowercased()
}

func normalizeAgentSizeRatio<K: CodingKey>(_ raw: CGFloat, percentKey key: K) throws -> CGFloat {
    guard raw.isFinite, raw > 0 else {
        throw DecodingError.dataCorrupted(.init(codingPath: [key], debugDescription: "size must be greater than 0"))
    }
    let ratio = raw > 1 ? raw / 100 : raw
    guard ratio > 0, ratio <= 1 else {
        throw DecodingError.dataCorrupted(.init(codingPath: [key], debugDescription: "size must be a ratio from 0 to 1, or a percent from 1 to 100"))
    }
    return ratio
}

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

struct AgentWorkspaceLayout: Codable {
    let name: String
    let focusPane: AgentPaneRef?
    let layout: AgentLayoutNode
    let floating: [AgentPaneRef]?

    private enum CodingKeys: String, CodingKey {
        case name
        case focusPane = "focus"
        case layout
        case floating
    }

    @MainActor
    func validate(appendTo errors: inout [String]) async throws {
        var orderedWindowIds: [UInt32] = []
        layout.collectWindowIds(result: &orderedWindowIds)
        for ref in floating ?? [] {
            ref.resolveNode()?.allLeafWindowsRecursive.forEach { orderedWindowIds.append($0.windowId) }
        }

        let windowIds = Set(orderedWindowIds)
        for windowId in duplicateAgentWindowIds(in: orderedWindowIds) {
            errors.append("setWorkspaceLayout '\(name)': window \(windowId) appears more than once")
        }
        for windowId in windowIds where Window.get(byId: windowId) == nil {
            errors.append("setWorkspaceLayout '\(name)': window \(windowId) does not exist")
        }
        for ref in floating ?? [] where ref.resolveNode() == nil {
            errors.append("setWorkspaceLayout '\(name)': floating pane does not exist")
        }
    }

    @MainActor
    func apply() async throws {
        let existedBefore = Workspace.existing(byName: name) != nil
        let workspace = Workspace.get(byName: name)
        if !existedBefore {
            workspace.assignProject(focus.workspace.projectId)
        }
        workspace.seedMonitorIfNeeded(focusPane?.resolveNode()?.nodeMonitor ?? focus.workspace.workspaceMonitor)
        let oldWindows = workspace.allLeafWindowsRecursive
        var referenced: Set<UInt32> = []
        layout.collectWindowIds(result: &referenced)
        for ref in floating ?? [] {
            ref.resolveNode()?.allLeafWindowsRecursive.forEach { referenced.insert($0.windowId) }
        }

        workspace.rootTilingContainer.unbindFromParent()
        switch layout {
            case .split:
                _ = try await layout.bind(into: workspace, index: INDEX_BIND_LAST)
            case .window, .tabGroup:
                _ = try await layout.bind(into: workspace.rootTilingContainer, index: INDEX_BIND_LAST)
        }
        for ref in floating ?? [] {
            if let node = ref.resolveNode(), let window = node as? Window {
                window.bindAsFloatingWindow(to: workspace)
            }
        }

        let root = workspace.rootTilingContainer
        for window in oldWindows where !referenced.contains(window.windowId) && window.isBound {
            if window.nodeWorkspace == nil || window.nodeWorkspace == workspace {
                window.bind(to: root, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            }
        }
        layout.applySizeRatios(to: root)
        if let focusNode = focusPane?.resolveNode() {
            _ = focusNode.mostRecentWindowRecursive?.focusWindow()
        }
    }
}

indirect enum AgentLayoutNode: Codable {
    case split(direction: AgentLayoutDirection, children: [AgentLayoutNode], size: CGFloat?)
    case window(windowId: UInt32, size: CGFloat?)
    case tabGroup(tabGroupId: String?, tabs: [UInt32], activeWindowId: UInt32?, size: CGFloat?)

    private enum CodingKeys: String, CodingKey {
        case kind
        case direction
        case children
        case windowId
        case tabGroupId
        case tabs
        case activeWindowId
        case size
        case sizePercent
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
            case "split":
                self = .split(
                    direction: try container.decode(AgentLayoutDirection.self, forKey: .direction),
                    children: try container.decode([AgentLayoutNode].self, forKey: .children),
                    size: try container.decodeAgentSizeRatioIfPresent(sizeKey: .size, percentKey: .sizePercent),
                )
            case "window":
                self = .window(
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                    size: try container.decodeAgentSizeRatioIfPresent(sizeKey: .size, percentKey: .sizePercent),
                )
            case "tabGroup":
                self = .tabGroup(
                    tabGroupId: try container.decodeIfPresent(String.self, forKey: .tabGroupId),
                    tabs: try container.decode([UInt32].self, forKey: .tabs),
                    activeWindowId: try container.decodeIfPresent(UInt32.self, forKey: .activeWindowId),
                    size: try container.decodeAgentSizeRatioIfPresent(sizeKey: .size, percentKey: .sizePercent),
                )
            default:
                throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown layout node kind '\(kind)'")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .split(let direction, let children, let size):
                try container.encode("split", forKey: .kind)
                try container.encode(direction, forKey: .direction)
                try container.encode(children, forKey: .children)
                try container.encodeIfPresent(size, forKey: .size)
            case .window(let windowId, let size):
                try container.encode("window", forKey: .kind)
                try container.encode(windowId, forKey: .windowId)
                try container.encodeIfPresent(size, forKey: .size)
            case .tabGroup(let tabGroupId, let tabs, let activeWindowId, let size):
                try container.encode("tabGroup", forKey: .kind)
                try container.encodeIfPresent(tabGroupId, forKey: .tabGroupId)
                try container.encode(tabs, forKey: .tabs)
                try container.encodeIfPresent(activeWindowId, forKey: .activeWindowId)
                try container.encodeIfPresent(size, forKey: .size)
        }
    }

    func collectWindowIds(result: inout Set<UInt32>) {
        switch self {
            case .split(_, let children, _):
                for child in children { child.collectWindowIds(result: &result) }
            case .window(let windowId, _):
                result.insert(windowId)
            case .tabGroup(_, let tabs, _, _):
                for tab in tabs { result.insert(tab) }
        }
    }

    func collectWindowIds(result: inout [UInt32]) {
        switch self {
            case .split(_, let children, _):
                for child in children { child.collectWindowIds(result: &result) }
            case .window(let windowId, _):
                result.append(windowId)
            case .tabGroup(_, let tabs, _, _):
                result.append(contentsOf: tabs)
        }
    }

    @MainActor
    func bind(into parent: NonLeafTreeNodeObject, index: Int) async throws -> TreeNode? {
        switch self {
            case .split(let direction, let children, _):
                let container = TilingContainer(parent: parent, adaptiveWeight: WEIGHT_AUTO, direction.orientation, .tiles, index: index)
                for child in children {
                    _ = try await child.bind(into: container, index: INDEX_BIND_LAST)
                }
                return container
            case .window(let windowId, _):
                guard let window = Window.get(byId: windowId) else { return nil }
                window.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: index)
                return window
            case .tabGroup(_, let tabs, let activeWindowId, _):
                guard !tabs.isEmpty else { return nil }
                let container = TilingContainer(parent: parent, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: index)
                for tab in tabs {
                    Window.get(byId: tab)?.bind(to: container, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                }
                if let activeWindowId {
                    Window.get(byId: activeWindowId)?.markAsMostRecentChild()
                }
                return container
        }
    }

    @MainActor
    func applySizeRatios(to node: TreeNode) {
        guard case .split(_, let childSpecs, _) = self,
              let container = node as? TilingContainer,
              container.layout == .tiles
        else { return }

        applyAgentSizeRatios(to: container, childSpecs: childSpecs)
        for (child, childSpec) in zip(container.children, childSpecs) {
            childSpec.applySizeRatios(to: child)
        }
    }

    var sizeRatio: CGFloat? {
        switch self {
            case .split(_, _, let size), .window(_, let size), .tabGroup(_, _, _, let size):
                size
        }
    }
}

enum AgentLayoutDirection: String, Codable {
    case horizontal
    case vertical

    var orientation: Orientation { self == .horizontal ? .h : .v }
}

