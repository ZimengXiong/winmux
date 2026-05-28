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
