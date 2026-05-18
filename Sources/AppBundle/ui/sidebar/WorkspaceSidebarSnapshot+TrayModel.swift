import Foundation

@MainActor
func workspaceSidebarSnapshot(from model: TrayMenuModel) -> WorkspaceSidebarSnapshot {
    WorkspaceSidebarSnapshot(
        workspaces: model.workspaceSidebarWorkspaces,
        projects: model.workspaceSidebarProjects,
        selectedProjectId: model.workspaceSidebarSelectedProjectId,
        monitorScopes: model.workspaceSidebarMonitorScopes,
        selectedMonitorScopeId: model.workspaceSidebarSelectedMonitorScopeId,
        focusedMonitorScopeId: model.workspaceSidebarFocusedMonitorScopeId,
        showsMonitorSelector: model.workspaceSidebarShowsMonitorSelector,
        visibleWidth: model.workspaceSidebarVisibleWidth,
        layout: workspaceSidebarLayoutSnapshot(),
        topPadding: model.workspaceSidebarTopPadding,
        hoveredWorkspaceName: model.workspaceSidebarHoveredWorkspaceName,
        dropPreview: model.workspaceSidebarDropPreview
    )
}
