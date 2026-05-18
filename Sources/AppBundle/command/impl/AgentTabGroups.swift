@MainActor
func resolveAgentTabGroup(_ id: String, context: AgentApplyContext? = nil) -> TilingContainer? {
    if let alias = context?.tabGroupAliases[id] {
        return alias
    }
    return Workspace.all
        .lazy
        .flatMap { $0.rootTilingContainer.allAgentTabGroupsRecursive }
        .first { agentTabGroupId($0) == id }
}

@MainActor
func agentTabGroupId(_ group: TilingContainer) -> String {
    let firstWindowId = group.agentTabWindows.first?.windowId ?? group.anyLeafWindowRecursive?.windowId ?? 0
    return "tabgroup-\(firstWindowId)"
}

func agentPaneIdForTabGroup(tabGroupId: String) -> String {
    "pane-\(tabGroupId)"
}

@MainActor
func reorderAgentTabGroup(_ group: TilingContainer, tabs: [UInt32]) {
    for tab in tabs {
        Window.get(byId: tab)?.bind(to: group, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
}
