import AppKit

@MainActor
func buildWorkspaceSidebarModelState() async -> WorkspaceSidebarModelState {
    let currentFocus = focus
    let availableMonitors = sortedMonitors
    let focusedMonitorScopeId = workspaceSidebarMonitorScopeId(for: currentFocus.workspace.workspaceMonitor)
    let monitorScopes = buildWorkspaceSidebarMonitorScopes(
        sortedMonitors: availableMonitors,
        focusedMonitorScopeId: focusedMonitorScopeId,
    )
    let activeProjectId = currentFocus.workspace.projectId
    let projects = buildWorkspaceSidebarProjectViewModels()
    let workspaces = await buildWorkspaceSidebarWorkspaceViewModels(
        currentFocus: currentFocus,
        workspaceLabels: config.workspaceSidebar.workspaceLabels,
        availableMonitors: availableMonitors,
    )
    let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspaceSidebarResolvedPanelMonitor())
    return WorkspaceSidebarModelState(
        workspaces: workspaces,
        projects: projects,
        activeProjectId: activeProjectId,
        monitorScopes: monitorScopes,
        focusedMonitorScopeId: focusedMonitorScopeId,
        showsMonitorSelector: availableMonitors.count > 1,
        topPadding: CGFloat(gaps.outer.top),
        hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
    )
}
