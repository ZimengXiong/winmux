import Foundation

@MainActor
func workspaceSidebarSnapshot(from model: TrayMenuModel) -> WorkspaceSidebarSnapshot {
    WorkspaceSidebarSnapshot(
        workspaces: model.workspaceSidebarWorkspaces,
        projects: model.workspaceSidebarProjects,
        selectedProjectId: model.workspaceSidebarSelectedProjectId,
        activeProjectId: model.workspaceSidebarActiveProjectId,
        monitorScopes: model.workspaceSidebarMonitorScopes,
        selectedMonitorScopeId: model.workspaceSidebarSelectedMonitorScopeId,
        targetMonitorScopeId: model.workspaceSidebarTargetMonitorScopeId,
        focusedMonitorScopeId: model.workspaceSidebarFocusedMonitorScopeId,
        visibleWidth: model.workspaceSidebarVisibleWidth,
        hoveredWorkspaceName: model.workspaceSidebarHoveredWorkspaceName,
        dropPreview: model.workspaceSidebarDropPreview,
        configuration: workspaceSidebarConfiguration(),
    )
}
