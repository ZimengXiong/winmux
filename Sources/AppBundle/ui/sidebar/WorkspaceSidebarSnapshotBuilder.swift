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
        visibleWidth: TrayMenuModel.shared.workspaceSidebarVisibleWidth,
        hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
        dropPreview: TrayMenuModel.shared.workspaceSidebarDropPreview,
        configuration: workspaceSidebarConfiguration(),
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
    TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector = snapshot.configuration.showMonitorSelector
    TrayMenuModel.shared.workspaceSidebarVisibleWidth = snapshot.visibleWidth
    TrayMenuModel.shared.workspaceSidebarTopPadding = snapshot.configuration.topPadding
    TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = snapshot.hoveredWorkspaceName
    TrayMenuModel.shared.workspaceSidebarDropPreview = snapshot.dropPreview
}

@MainActor
func workspaceSidebarConfiguration() -> WorkspaceSidebarConfiguration {
    WorkspaceSidebarConfiguration(
        collapsedWidth: CGFloat(config.workspaceSidebar.collapsedWidth),
        expandedWidth: CGFloat(config.workspaceSidebar.width),
        topPadding: TrayMenuModel.shared.workspaceSidebarTopPadding,
        showMonitorSelector: TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector,
        showsDate: config.workspaceSidebar.showDate,
        showsStatusPills: config.workspaceSidebar.showStatusPills,
    )
}
