import AppKit

@MainActor
func clearWorkspaceSidebarModelState() {
    if !TrayMenuModel.shared.workspaceSidebarWorkspaces.isEmpty {
        TrayMenuModel.shared.workspaceSidebarWorkspaces = []
    }
    if !TrayMenuModel.shared.workspaceSidebarMonitorScopes.isEmpty {
        TrayMenuModel.shared.workspaceSidebarMonitorScopes = []
    }
    if !TrayMenuModel.shared.workspaceSidebarProjects.isEmpty {
        TrayMenuModel.shared.workspaceSidebarProjects = []
    }
    TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector = false
    WorkspaceSidebarPanel.refreshAll()
}

@MainActor
func applyWorkspaceSidebarModelState(_ state: WorkspaceSidebarModelState, previousTopPadding: CGFloat) {
    let didMonitorScopeChange =
        TrayMenuModel.shared.workspaceSidebarMonitorScopes != state.monitorScopes ||
        TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId != state.selectedMonitorScopeId ||
        TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId != state.focusedMonitorScopeId ||
        TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector != state.showsMonitorSelector
    let didProjectChange =
        TrayMenuModel.shared.workspaceSidebarProjects != state.projects ||
        TrayMenuModel.shared.workspaceSidebarSelectedProjectId != state.selectedProjectId

    updateWorkspaceSidebarTrayModel(with: state)
    WorkspaceSidebarPanel.syncVisiblePanelModelsFromShared()
    let didWorkspaceChange = TrayMenuModel.shared.workspaceSidebarWorkspaces != state.workspaces
    if didWorkspaceChange {
        TrayMenuModel.shared.workspaceSidebarWorkspaces = state.workspaces
        WorkspaceSidebarPanel.syncVisiblePanelModelsFromShared()
    }
    if didWorkspaceChange ||
        state.topPadding != previousTopPadding ||
        didMonitorScopeChange ||
        didProjectChange ||
        WorkspaceSidebarPanel.visiblePanels.isEmpty
    {
        WorkspaceSidebarPanel.refreshAll()
    }
}

@MainActor
private func updateWorkspaceSidebarTrayModel(with state: WorkspaceSidebarModelState) {
    TrayMenuModel.shared.workspaceSidebarTopPadding = state.topPadding
    TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = state.hoveredWorkspaceName
    TrayMenuModel.shared.workspaceSidebarProjects = state.projects
    TrayMenuModel.shared.workspaceSidebarSelectedProjectId = state.selectedProjectId
    TrayMenuModel.shared.workspaceSidebarActiveProjectId = state.activeProjectId
    TrayMenuModel.shared.workspaceSidebarMonitorScopes = state.monitorScopes
    TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId = state.selectedMonitorScopeId
    TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId = state.focusedMonitorScopeId
    TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector = state.showsMonitorSelector
}
