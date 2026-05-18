import Common

@MainActor
func resetWorkspaceNameGenerationStateForTests() {
    for workspace in Workspace.all {
        workspace.projectId = workspaceProjectDefaultId
    }
    winMuxWorkspaceState.resetProjects(defaultProjectName: workspaceProjectDisplayName(workspaceProjectDefaultId, fallbackName: "Default"))
}

@MainActor
func resetWinMuxWorkspaceStateForTests() {
    for workspace in Workspace.all {
        workspace.lifecycle = .durable
    }
    winMuxWorkspaceState.resetWorkspaceRegistryForTests(
        defaultProjectName: workspaceProjectDisplayName(workspaceProjectDefaultId, fallbackName: "Default"),
    )
}

@MainActor
func activateLaneFallbackWorkspaceForTests(on monitor: Monitor) -> Workspace {
    let workspace = getOrCreateLaneFallbackWorkspace(for: monitor)
    check(monitor.setActiveWorkspace(workspace))
    return workspace
}
