import Common

@MainActor
func nextSidebarDraftWorkspaceName() -> String {
    clearOrphanedWorkspaceSidebarLabels()
    let nextIndex = lowestUnusedPositiveIndex(Set(winMuxWorkspaceState.workspaceIdByName.keys.compactMap(sidebarDraftWorkspaceIndex)))
    return "\(sidebarDraftWorkspacePrefix)\(nextIndex)"
}

@MainActor
func nextSidebarCreatedWorkspaceName(projectId: WorkspaceProjectId = workspaceProjectDefaultId, monitor: Monitor = mainMonitor) -> String {
    nextAutomaticWorkspaceName(projectId: projectId, monitor: monitor)
}

func isSidebarDraftWorkspaceName(_ name: String) -> Bool {
    name.hasPrefix(sidebarDraftWorkspacePrefix)
}

func sidebarDraftWorkspaceIndex(_ name: String) -> Int? {
    guard isSidebarDraftWorkspaceName(name) else { return nil }
    let suffix = name.replacingOccurrences(of: sidebarDraftWorkspacePrefix, with: "")
    return Int(suffix)
}

@MainActor
func clearWorkspaceSidebarLabelIfNeeded(_ workspaceName: String) {
    guard config.workspaceSidebar.workspaceLabels.removeValue(forKey: workspaceName) != nil else { return }
    if !isUnitTest {
        try? persistWorkspaceSidebarLabel(workspaceName: workspaceName, label: nil)
    }
}

@MainActor
func clearSidebarDraftWorkspaceLabelIfNeeded(_ workspaceName: String) {
    guard isSidebarDraftWorkspaceName(workspaceName) else { return }
    clearWorkspaceSidebarLabelIfNeeded(workspaceName)
}

@MainActor
func clearOrphanedWorkspaceSidebarLabels() {
    for workspaceName in config.workspaceSidebar.workspaceLabels.keys
    where winMuxWorkspaceState.workspace(named: workspaceName) == nil
    {
        clearWorkspaceSidebarLabelIfNeeded(workspaceName)
    }
}

@MainActor
func workspaceDefaultDisplayName(_ workspaceName: String) -> String {
    if let workspace = Workspace.existing(byName: workspaceName) {
        guard workspace.usesAutomaticDisplayName else { return workspaceName }
        if let index = automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: focus.workspace)
            ?? automaticWorkspaceDisplayIndexFallback(workspaceName)
        {
            return "Workspace \(index)"
        }
        return workspaceName
    }
    if let index = sidebarDraftWorkspaceIndex(workspaceName) {
        return "Workspace \(index)"
    }
    return workspaceName
}

@MainActor
func workspaceDisplayName(_ workspaceName: String) -> String {
    if let configuredName = config.workspaceSidebar.workspaceLabels[workspaceName]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !configuredName.isEmpty
    {
        return configuredName
    }
    return workspaceDefaultDisplayName(workspaceName)
}
