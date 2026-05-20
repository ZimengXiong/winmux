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
    previousSelectedProjectId: WorkspaceProjectId,
    previousActiveProjectId: WorkspaceProjectId,
    fallbackProjectId: WorkspaceProjectId,
) -> WorkspaceProjectId {
    if previousSelectedProjectId == previousActiveProjectId,
       validProjectIds.contains(fallbackProjectId)
    {
        return fallbackProjectId
    }
    if validProjectIds.contains(previousSelectedProjectId) {
        return previousSelectedProjectId
    }
    if validProjectIds.contains(fallbackProjectId) {
        return fallbackProjectId
    }
    if validProjectIds.contains(workspaceProjectDefaultId) {
        return workspaceProjectDefaultId
    }
    return validProjectIds.sorted().first ?? workspaceProjectDefaultId
}
