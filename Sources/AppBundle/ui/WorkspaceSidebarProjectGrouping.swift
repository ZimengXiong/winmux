import Foundation

func workspaceSidebarVisibleWorkspacesByProject(
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
    selectedScopeId: String,
    focusedMonitorScopeId: String,
) -> [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]] {
    var result: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]] = [:]
    for workspace in workspaces where workspaceSidebarWorkspaceMatchesScope(
        workspaceMonitorScopeId: workspace.monitorScopeId,
        selectedScopeId: selectedScopeId,
        focusedMonitorScopeId: focusedMonitorScopeId,
    ) {
        result[workspace.projectId, default: []].append(workspace)
    }
    return result
}

func workspaceSidebarWorkspaceIsInUseOnOtherDisplay(
    _ workspace: WorkspaceSidebarWorkspaceViewModel,
    selectedScopeId: String,
) -> Bool {
    guard selectedScopeId != workspaceSidebarDefaultScopeId,
          selectedScopeId != workspaceSidebarFocusedScopeId,
          selectedScopeId != workspaceSidebarAllScopeId,
          workspace.isVisible,
          workspace.monitorScopeId != workspaceSidebarAllScopeId
    else {
        return false
    }
    return workspace.monitorScopeId != selectedScopeId
}
