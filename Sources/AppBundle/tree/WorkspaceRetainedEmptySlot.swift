@MainActor
func workspaceIsRetainedEmptySlot(_ workspace: Workspace) -> Bool {
    retainedEmptyWorkspaceIdsByScope()[WorkspaceScope(projectId: workspace.projectId)] == workspace.id
}

@MainActor
func retainedEmptyWorkspaceIdsByScope() -> [WorkspaceScope: WorkspaceId] {
    let scopes = Set(Workspace.all.filter { !$0.isArchived }.map { WorkspaceScope(projectId: $0.projectId) })
    return Dictionary(
        uniqueKeysWithValues: scopes.compactMap { scope in
            retainedEmptyWorkspaceId(in: scope).map { (scope, $0) }
        },
    )
}

@MainActor
func retainedEmptyWorkspaceId(in scope: WorkspaceScope) -> WorkspaceId? {
    let orderedWorkspaces = orderedWorkspaces(in: scope)
    let ordinaryEmptyWorkspaces = orderedWorkspaces.filter(\.isOrdinaryEmptySlot).sorted {
        if $0.lifecycle != $1.lifecycle {
            return $0.lifecycle == .durable
        }
        return $0 < $1
    }
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
    winMuxWorkspaceState.monitorViewportsById.values.contains { viewport in
        viewport.activeWorkspaceId
            .flatMap { winMuxWorkspaceState.workspaceById[$0] }?
            .projectId == scope.projectId
    }
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
