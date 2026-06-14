import AppKit
import Common
import Foundation

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

    var sizeRatio: CGFloat? {
        switch self {
            case .split(_, _, let size), .window(_, let size), .tabGroup(_, _, _, let size):
                size
        }
    }
}

extension AgentLayoutNode {
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
}

extension AgentLayoutNode {
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
}

extension AgentLayoutNode {
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
}
