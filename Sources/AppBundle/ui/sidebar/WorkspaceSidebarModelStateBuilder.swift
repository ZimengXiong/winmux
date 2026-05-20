import AppKit

@MainActor
func buildWorkspaceSidebarModelState(previousSelectedMonitorScopeId: String) async -> WorkspaceSidebarModelState {
    let currentFocus = focus
    let availableMonitors = sortedMonitors
    let focusedMonitorScopeId = workspaceSidebarMonitorScopeId(for: currentFocus.workspace.workspaceMonitor)
    let monitorScopes = buildWorkspaceSidebarMonitorScopes(
        sortedMonitors: availableMonitors,
        focusedMonitorScopeId: focusedMonitorScopeId,
    )
    let selectedMonitorScopeId = resolvedWorkspaceSidebarSelectedMonitorScopeId(
        previousSelectedMonitorScopeId,
        monitorScopes: monitorScopes,
        availableMonitorCount: availableMonitors.count,
    )
    let projectMonitor = workspaceSidebarSelectedProjectMonitor(
        selectedScopeId: previousSelectedMonitorScopeId,
        focusedMonitor: currentFocus.workspace.workspaceMonitor,
        sortedMonitors: availableMonitors,
    )
    let activeProjectId = activeWorkspaceProjectId(for: projectMonitor)
    let projects = buildWorkspaceSidebarProjectViewModels()
    let workspaces = await buildWorkspaceSidebarWorkspaceViewModels(
        currentFocus: currentFocus,
        workspaceLabels: config.workspaceSidebar.workspaceLabels,
        availableMonitors: availableMonitors,
    )
    let visibleWorkspaceNames = visibleWorkspaceNamesForSidebar(
        workspaces: workspaces,
        selectedMonitorScopeId: selectedMonitorScopeId,
        focusedMonitorScopeId: focusedMonitorScopeId,
    )
    let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspaceSidebarResolvedPanelMonitor())
    return WorkspaceSidebarModelState(
        workspaces: workspaces,
        projects: projects,
        selectedProjectId: resolvedWorkspaceSidebarSelectedProjectId(
            validProjectIds: Set(projects.map(\.id)),
            previousSelectedProjectId: TrayMenuModel.shared.workspaceSidebarSelectedProjectId,
            previousActiveProjectId: TrayMenuModel.shared.workspaceSidebarActiveProjectId,
            fallbackProjectId: activeProjectId,
        ),
        activeProjectId: activeProjectId,
        monitorScopes: monitorScopes,
        selectedMonitorScopeId: selectedMonitorScopeId,
        focusedMonitorScopeId: focusedMonitorScopeId,
        showsMonitorSelector: availableMonitors.count > 1,
        topPadding: CGFloat(gaps.outer.top),
        hoveredWorkspaceName: sanitizedWorkspaceSidebarHoveredWorkspaceName(
            visibleWorkspaceNames: visibleWorkspaceNames,
            hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
        ),
    )
}

func resolvedWorkspaceSidebarSelectedMonitorScopeId(
    _ selectedScopeId: String,
    monitorScopes: [WorkspaceSidebarMonitorScopeViewModel],
    availableMonitorCount: Int,
) -> String {
    let validScopeIds = Set(monitorScopes.map(\.id))
    if validScopeIds.contains(selectedScopeId) {
        return selectedScopeId
    }
    return workspaceSidebarDefaultScopeId
}
