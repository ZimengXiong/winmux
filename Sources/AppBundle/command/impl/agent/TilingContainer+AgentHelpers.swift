extension TilingContainer {
    @MainActor
    var allAgentTabGroupsRecursive: [TilingContainer] {
        var result: [TilingContainer] = []
        func visit(_ node: TreeNode) {
            guard let container = node as? TilingContainer else { return }
            if container.isWindowTabGroup {
                result.append(container)
                return
            }
            for child in container.children {
                visit(child)
            }
        }
        visit(self)
        return result
    }

    @MainActor
    var agentTabWindows: [Window] {
        children.compactMap { $0.tabRepresentativeWindow ?? $0.mostRecentWindowRecursive ?? $0.anyLeafWindowRecursive }
    }

    @MainActor
    func agentRawLayoutNode() -> AgentRawLayoutNode {
        if isWindowTabGroup {
            return .tabGroup(
                tabGroupId: agentTabGroupId(self),
                activeWindowId: tabActiveWindow?.windowId,
                tabs: agentTabWindows.map(\.windowId),
                size: agentSizeRatio,
            )
        }
        return .split(
            direction: orientation == .h ? .horizontal : .vertical,
            layout: layout.rawValue,
            size: agentSizeRatio,
            children: children.compactMap(agentRawLayoutChild),
        )
    }

    @MainActor
    func agentWorldLines(prefix: String) -> [String] {
        let nodeId = isWindowTabGroup
            ? "tabGroup:\(agentTabGroupId(self))"
            : "container:\(orientation.rawValue):\(layout.rawValue)"
        let weight = (parent as? TilingContainer).map { "|weight:\(getWeight($0.orientation))" } ?? ""
        var result = ["\(prefix)|\(nodeId)\(weight)|children:\(children.count)"]
        for (index, child) in children.enumerated() {
            let childPrefix = "\(prefix).\(index)"
            if let window = child as? Window {
                result.append("\(childPrefix)|window:\(window.windowId)|weight:\(window.getWeight(orientation))")
            } else if let container = child as? TilingContainer {
                result.append(contentsOf: container.agentWorldLines(prefix: childPrefix))
            }
        }
        return result
    }

    @MainActor
    private func agentRawLayoutChild(_ child: TreeNode) -> AgentRawLayoutNode? {
        if let window = child as? Window {
            return .window(windowId: window.windowId, size: window.agentSizeRatio)
        }
        if let container = child as? TilingContainer {
            return container.agentRawLayoutNode()
        }
        return nil
    }
}
