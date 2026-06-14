import Common

extension Workspace {
    @MainActor
    func agentPaneRelations() -> [AgentPaneRelation] {
        var byPane: [String: AgentPaneRelation] = [:]
        visitAgentPaneRelations(rootTilingContainer, byPane: &byPane)
        return Array(byPane.values)
    }

    @MainActor
    private func visitAgentPaneRelations(_ node: TreeNode, byPane: inout [String: AgentPaneRelation]) {
        guard let container = node as? TilingContainer, !container.isWindowTabGroup else { return }
        let childPaneIds = container.children.map(agentPaneIds)
        for index in childPaneIds.indices.dropLast() {
            for lhs in childPaneIds[index] {
                for rhs in childPaneIds[index + 1] {
                    setAgentPaneRelation(lhs, rhs, orientation: container.orientation, byPane: &byPane)
                }
            }
        }
        for child in container.children {
            visitAgentPaneRelations(child, byPane: &byPane)
        }
    }

    @MainActor
    private func setAgentPaneRelation(
        _ lhs: String,
        _ rhs: String,
        orientation: Orientation,
        byPane: inout [String: AgentPaneRelation],
    ) {
        if orientation == .h {
            setAgentPaneRelation(lhs, \.right, rhs, byPane: &byPane)
            setAgentPaneRelation(rhs, \.left, lhs, byPane: &byPane)
        } else {
            setAgentPaneRelation(lhs, \.below, rhs, byPane: &byPane)
            setAgentPaneRelation(rhs, \.above, lhs, byPane: &byPane)
        }
    }

    private func setAgentPaneRelation(
        _ paneId: String,
        _ keyPath: WritableKeyPath<AgentPaneRelation, String?>,
        _ value: String?,
        byPane: inout [String: AgentPaneRelation],
    ) {
        guard let value else { return }
        var item = byPane[paneId] ?? AgentPaneRelation(workspace: name, paneId: paneId)
        item[keyPath: keyPath] = value
        byPane[paneId] = item
    }

    @MainActor
    private func agentPaneIds(_ node: TreeNode) -> [String] {
        if let paneId = node.agentPaneId { return [paneId] }
        return node.children.flatMap(agentPaneIds)
    }
}
