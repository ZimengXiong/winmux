import Foundation

@MainActor
func makeWorkspaceSidebarActionsAdapter() -> WorkspaceSidebarActions {
    WorkspaceSidebarActions { action in
        handleWorkspaceSidebarAction(action)
    }
}

@MainActor
func handleWorkspaceSidebarAction(_ action: WorkspaceSidebarAction) {
    switch action {
        case .selectWorkspace(let name):
            focusWorkspaceFromSidebar(name)
        case .selectWindow(let windowId, let fallbackWorkspace):
            focusWindowFromSidebar(windowId, fallbackWorkspace: fallbackWorkspace)
        case .selectProject(let projectId):
            selectWorkspaceSidebarProject(projectId)
        case .createProject:
            createWorkspaceSidebarProject()
        case .renameProject(let projectId, let displayName):
            if let project = workspaceSidebarProjectViewModel(projectId) {
                renameWorkspaceSidebarProject(project, displayName: displayName)
            }
        case .setProjectColor(let projectId, let colorHex):
            if let project = workspaceSidebarProjectViewModel(projectId) {
                setWorkspaceSidebarProjectColor(project, colorHex: colorHex)
            }
        case .deleteProject(let projectId):
            if let project = workspaceSidebarProjectViewModel(projectId) {
                deleteWorkspaceSidebarProject(project)
            }
        case .selectMonitorScope(let scopeId):
            selectWorkspaceSidebarMonitorScope(scopeId)
        case .createWorkspace:
            createWorkspaceFromSidebarButton()
        case .renameWorkspace(let name, let displayName):
            if let workspace = workspaceSidebarWorkspaceViewModel(name) {
                renameWorkspaceFromSidebar(workspace, displayName: displayName)
            }
        case .resetWorkspace(let name):
            if let workspace = workspaceSidebarWorkspaceViewModel(name) {
                resetWorkspaceNameFromSidebar(workspace)
            }
        case .deleteWorkspace(let name):
            if let workspace = workspaceSidebarWorkspaceViewModel(name) {
                deleteWorkspaceFromSidebar(workspace)
            }
        case .hoverWorkspace(let name, let isHovering):
            TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = nextWorkspaceSidebarHoveredWorkspaceName(
                currentHoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
                workspaceName: name,
                isHovering: isHovering,
            )
        case .updateWindowDrag(let windowId, let subject):
            updateSidebarWindowDrag(windowId, subject: subject)
        case .finishWindowDrag:
            finishSidebarWindowDrag()
        case .setDropTargets(let targets):
            WorkspaceSidebarPanel.shared.updateDropTargets(targets)
    }
}

@MainActor
private func workspaceSidebarProjectViewModel(_ id: WorkspaceProjectId) -> WorkspaceSidebarProjectViewModel? {
    TrayMenuModel.shared.workspaceSidebarProjects.first { $0.id == id }
}

@MainActor
private func workspaceSidebarWorkspaceViewModel(_ name: String) -> WorkspaceSidebarWorkspaceViewModel? {
    TrayMenuModel.shared.workspaceSidebarWorkspaces.first { $0.name == name }
}
