@MainActor
func agentMoveWindowToWorkspace(_ window: Window, _ targetWorkspace: Workspace, focusFollowsWindow: Bool) -> Bool {
    moveWindowToWorkspace(window, targetWorkspace, CmdIo(stdin: .emptyStdin), focusFollowsWindow: focusFollowsWindow, failIfNoop: false)
}

@MainActor
func placeAgentPane(_ source: TreeNode, relation: AgentPaneRelationKind, target: TreeNode) {
    if source == target || source.parentsWithSelf.contains(target) || target.parentsWithSelf.contains(source) {
        return
    }
    if let insertion = target.agentNearestInsertionParent(orientation: relation.orientation) {
        placeAgentPane(source, relation: relation, insertion: insertion)
        return
    }

    _ = source.unbindFromParent()
    guard target.parent != nil else { return }
    let targetBinding = target.unbindFromParent()
    let newParent = TilingContainer(parent: targetBinding.parent, adaptiveWeight: targetBinding.adaptiveWeight, relation.orientation, .tiles, index: targetBinding.index)
    if relation.sourceIsAfterTarget {
        target.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        source.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    } else {
        source.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        target.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
    source.mostRecentWindowRecursive?.markAsMostRecentChild()
}

@MainActor
private func placeAgentPane(
    _ source: TreeNode,
    relation: AgentPaneRelationKind,
    insertion: (parent: TilingContainer, anchor: TreeNode),
) {
    var insertIndex = insertion.anchor.ownIndex.orDie() + (relation.sourceIsAfterTarget ? 1 : 0)
    if source.parent === insertion.parent, let sourceIndex = source.ownIndex, sourceIndex < insertIndex {
        insertIndex -= 1
    }
    source.bind(to: insertion.parent, adaptiveWeight: WEIGHT_AUTO, index: insertIndex)
    source.mostRecentWindowRecursive?.markAsMostRecentChild()
}
