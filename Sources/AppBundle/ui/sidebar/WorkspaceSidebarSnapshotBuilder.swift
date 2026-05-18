import Foundation

@MainActor
func buildWorkspaceSidebarSnapshot() async -> WorkspaceSidebarSnapshot {
    guard TrayMenuModel.shared.isEnabled, config.workspaceSidebar.enabled else {
        return .empty
    }

    await refreshWorkspaceSidebarModelState()
    return WorkspaceSidebarSnapshot(
        workspaces: TrayMenuModel.shared.workspaceSidebarWorkspaces,
        projects: TrayMenuModel.shared.workspaceSidebarProjects,
        selectedProjectId: TrayMenuModel.shared.workspaceSidebarSelectedProjectId,
        monitorScopes: TrayMenuModel.shared.workspaceSidebarMonitorScopes,
        selectedMonitorScopeId: TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId,
        focusedMonitorScopeId: TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId,
        showsMonitorSelector: TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector,
        visibleWidth: TrayMenuModel.shared.workspaceSidebarVisibleWidth,
        topPadding: TrayMenuModel.shared.workspaceSidebarTopPadding,
        hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
        dropPreview: TrayMenuModel.shared.workspaceSidebarDropPreview,
    )
}

@MainActor
func refreshWorkspaceSidebarModelState() async {
    await updateWorkspaceSidebarModel()
}

@MainActor
func applyWorkspaceSidebarSnapshotToTrayModel(_ snapshot: WorkspaceSidebarSnapshot) {
    TrayMenuModel.shared.workspaceSidebarWorkspaces = snapshot.workspaces
    TrayMenuModel.shared.workspaceSidebarProjects = snapshot.projects
    TrayMenuModel.shared.workspaceSidebarSelectedProjectId = snapshot.selectedProjectId
    TrayMenuModel.shared.workspaceSidebarMonitorScopes = snapshot.monitorScopes
    TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId = snapshot.selectedMonitorScopeId
    TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId = snapshot.focusedMonitorScopeId
    TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector = snapshot.showsMonitorSelector
    TrayMenuModel.shared.workspaceSidebarVisibleWidth = snapshot.visibleWidth
    TrayMenuModel.shared.workspaceSidebarTopPadding = snapshot.topPadding
    TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = snapshot.hoveredWorkspaceName
    TrayMenuModel.shared.workspaceSidebarDropPreview = snapshot.dropPreview
}
