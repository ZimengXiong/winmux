func sanitizedWorkspaceSidebarHoveredWorkspaceName(
    visibleWorkspaceNames: Set<String>,
    hoveredWorkspaceName: String?,
) -> String? {
    guard let hoveredWorkspaceName,
          visibleWorkspaceNames.contains(hoveredWorkspaceName)
    else {
        return nil
    }
    return hoveredWorkspaceName
}

func resolvedWorkspaceSidebarSelectedProjectId(
    validProjectIds: Set<WorkspaceProjectId>,
    activeProjectId: WorkspaceProjectId,
) -> WorkspaceProjectId {
    if validProjectIds.contains(activeProjectId) {
        return activeProjectId
    }
    if validProjectIds.contains(workspaceProjectDefaultId) {
        return workspaceProjectDefaultId
    }
    return validProjectIds.sorted().first ?? workspaceProjectDefaultId
}
