import Common

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
