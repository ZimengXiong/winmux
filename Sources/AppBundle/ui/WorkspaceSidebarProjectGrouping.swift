import Foundation

func workspaceSidebarVisibleWorkspacesByProject(
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
    selectedScopeId: String,
    focusedMonitorScopeId: String,
    browsedProjectId: WorkspaceProjectId? = nil,
) -> [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]] {
    var result: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]] = [:]
    for workspace in workspaces {
        if workspace.projectId != browsedProjectId &&
            !workspaceSidebarWorkspaceMatchesScope(
                workspace,
                selectedScopeId: selectedScopeId,
                focusedMonitorScopeId: focusedMonitorScopeId,
            )
        {
            continue
        }
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
