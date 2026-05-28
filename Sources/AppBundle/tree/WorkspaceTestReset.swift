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
func activateMonitorViewportFallbackWorkspaceForTests(on monitor: Monitor) -> Workspace {
    let workspace = getOrCreateMonitorViewportFallbackWorkspace(for: monitor)
    check(monitor.setActiveWorkspace(workspace))
    return workspace
}
