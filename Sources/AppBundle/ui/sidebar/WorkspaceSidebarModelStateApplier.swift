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
    WorkspaceSidebarPanel.shared.refresh()
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
    let didWorkspaceChange = TrayMenuModel.shared.workspaceSidebarWorkspaces != state.workspaces
    if didWorkspaceChange {
        TrayMenuModel.shared.workspaceSidebarWorkspaces = state.workspaces
    }
    if didWorkspaceChange ||
        state.topPadding != previousTopPadding ||
        didMonitorScopeChange ||
        didProjectChange ||
        !WorkspaceSidebarPanel.shared.isVisible
    {
        WorkspaceSidebarPanel.shared.refresh()
    }
}

@MainActor
private func updateWorkspaceSidebarTrayModel(with state: WorkspaceSidebarModelState) {
    TrayMenuModel.shared.workspaceSidebarTopPadding = state.topPadding
    TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = state.hoveredWorkspaceName
    TrayMenuModel.shared.workspaceSidebarProjects = state.projects
    TrayMenuModel.shared.workspaceSidebarSelectedProjectId = state.selectedProjectId
    TrayMenuModel.shared.workspaceSidebarMonitorScopes = state.monitorScopes
    TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId = state.selectedMonitorScopeId
    TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId = state.focusedMonitorScopeId
    TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector = state.showsMonitorSelector
}
