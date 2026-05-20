@MainActor
func workspaceIsRetainedEmptySlot(_ workspace: Workspace) -> Bool {
    retainedEmptyWorkspaceIdsByScope()[workspace.scope] == workspace.id
}

@MainActor
func retainedEmptyWorkspaceIdsByScope() -> [WorkspaceScope: WorkspaceId] {
    let scopes = Set(Workspace.all.filter { !$0.isArchived }.map(\.scope))
    return Dictionary(
        uniqueKeysWithValues: scopes.compactMap { scope in
            retainedEmptyWorkspaceId(in: scope).map { (scope, $0) }
        },
    )
}

@MainActor
func retainedEmptyWorkspaceId(in scope: WorkspaceScope) -> WorkspaceId? {
    guard workspaceScopeIsVisibleActiveProject(scope) else { return nil }
    let orderedWorkspaces = orderedWorkspaces(in: scope)
    let ordinaryEmptyWorkspaces = orderedWorkspaces.filter(\.isOrdinaryEmptySlot)
    guard !ordinaryEmptyWorkspaces.isEmpty else { return nil }

    let hasAnchors = orderedWorkspaces.contains(where: workspaceAnchorsEmptySlot)
    guard hasAnchors else {
        return ordinaryEmptyWorkspaces.first(where: \.isVisible)?.id ?? ordinaryEmptyWorkspaces.first?.id
    }

    if let visibleEmptyWorkspace = ordinaryEmptyWorkspaces.first(where: \.isVisible),
       workspaceHasAdjacentAnchor(visibleEmptyWorkspace, in: orderedWorkspaces)
    {
        return visibleEmptyWorkspace.id
    }
    return nil
}

@MainActor
func workspaceScopeIsVisibleActiveProject(_ scope: WorkspaceScope) -> Bool {
    guard let lane = winMuxWorkspaceState.lanesById[scope.laneId],
          let activeWorkspaceId = lane.activeWorkspaceId,
          let activeWorkspace = winMuxWorkspaceState.workspaceById[activeWorkspaceId]
    else {
        return false
    }
    return activeWorkspace.projectId == scope.projectId
}

@MainActor
func workspaceAnchorsEmptySlot(_ workspace: Workspace) -> Bool {
    workspaceHasLifecycleWindows(workspace) || workspace.isConfiguredPersistent
}

@MainActor
func workspaceHasAdjacentAnchor(_ workspace: Workspace, in orderedWorkspaces: [Workspace]) -> Bool {
    guard let index = orderedWorkspaces.firstIndex(of: workspace) else { return false }
    return orderedWorkspaces.getOrNil(atIndex: index - 1).map(workspaceAnchorsEmptySlot) == true ||
        orderedWorkspaces.getOrNil(atIndex: index + 1).map(workspaceAnchorsEmptySlot) == true
}
