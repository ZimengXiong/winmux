@MainActor
func orderedUserFacingWorkspaces(in scope: WorkspaceScope, focusedWorkspace: Workspace? = nil) -> [Workspace] {
    userFacingWorkspaces(orderedWorkspaces(in: scope), focusedWorkspace: focusedWorkspace)
}

@MainActor
func orderedUserFacingWorkspaces(in projectId: WorkspaceProjectId, focusedWorkspace: Workspace? = nil) -> [Workspace] {
    userFacingWorkspaces(orderedWorkspaces(in: projectId), focusedWorkspace: focusedWorkspace)
}

@MainActor
func workspaceHasSidebarVisibleWindows(_ workspace: Workspace) -> Bool {
    !workspace.rootTilingContainer.isEffectivelyEmpty ||
        !workspace.floatingWindows.isEmpty
}

@MainActor
func workspaceOwnedMinimizedWindows(_ workspace: Workspace) -> [Window] {
    macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self).filter {
        switch $0.layoutReason {
            case .macos(_, let prevWorkspaceName): prevWorkspaceName == workspace.name
            case .standard: false
        }
    }
}

@MainActor
func workspaceHasLifecycleWindows(_ workspace: Workspace) -> Bool {
    !workspace.isEffectivelyEmpty || !workspaceOwnedMinimizedWindows(workspace).isEmpty
}

@MainActor
func isUserFacingWorkspace(_ workspace: Workspace, focusedWorkspace: Workspace? = nil) -> Bool {
    !workspace.isArchived &&
        (
            workspaceHasSidebarVisibleWindows(workspace) ||
                workspace.isVisible ||
                workspace.isConfiguredPersistent ||
                !workspaceOwnedMinimizedWindows(workspace).isEmpty ||
                workspaceIsRetainedEmptySlot(workspace)
        )
}

@MainActor
func userFacingWorkspaces(_ workspaces: [Workspace], focusedWorkspace: Workspace? = nil) -> [Workspace] {
    workspaces.filter { isUserFacingWorkspace($0, focusedWorkspace: focusedWorkspace) }
}

@MainActor
func shouldShowWorkspaceInSidebar(_ workspace: Workspace, currentFocus: LiveFocus, isEditingWorkspace: Bool) -> Bool {
    isEditingWorkspace || isUserFacingWorkspace(workspace, focusedWorkspace: currentFocus.workspace)
}
