import AppKit

@MainActor
func workspaceScope(projectId: WorkspaceProjectId, monitor: Monitor) -> WorkspaceScope {
    WorkspaceScope(projectId: projectId)
}

@MainActor func getOrCreateLaneFallbackWorkspace(for monitor: Monitor) -> Workspace {
    getOrCreateLaneFallbackWorkspace(
        projectId: activeWorkspaceProjectId(for: monitor),
        for: monitor,
    )
}

@MainActor func getOrCreateLaneFallbackWorkspace(projectId: WorkspaceProjectId, for monitor: Monitor) -> Workspace {
    getOrCreateFallbackWorkspace(
        projectId: projectId,
        laneId: DisplayLaneId(monitor),
        monitor: monitor,
        excluding: nil,
    )
}

@MainActor func getOrCreateLaneFallbackWorkspace(
    projectId: WorkspaceProjectId,
    for monitor: Monitor,
    excluding excludedWorkspace: Workspace?,
) -> Workspace {
    getOrCreateFallbackWorkspace(
        projectId: projectId,
        laneId: DisplayLaneId(monitor),
        monitor: monitor,
        excluding: excludedWorkspace,
    )
}

@MainActor
func getOrCreateLaneFallbackWorkspace(forPoint point: CGPoint) -> Workspace {
    let monitor = point.monitorApproximation
    return getOrCreateFallbackWorkspace(
        projectId: activeWorkspaceProjectId(for: monitor),
        laneId: DisplayLaneId(topLeftCorner: point),
        monitor: monitor,
        excluding: nil,
    )
}

@MainActor
func getOrCreateFallbackWorkspace(
    projectId: WorkspaceProjectId,
    laneId: DisplayLaneId,
    monitor: Monitor,
    excluding excludedWorkspace: Workspace?,
) -> Workspace {
    let scope = WorkspaceScope(projectId: projectId)
    if let workspaceId = retainedEmptyWorkspaceId(in: scope),
       let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
       workspace != excludedWorkspace,
       workspaceIsAvailableForMonitor(workspace, monitor: monitor)
    {
        return workspace
    }
    if let workspace = projectWorkspaces(projectId: projectId)
        .first(where: {
            $0 != excludedWorkspace &&
                $0.isEffectivelyEmpty &&
                !$0.isArchived &&
                workspaceIsAvailableForMonitor($0, monitor: monitor)
        })
    {
        return workspace
    }
    let workspace = Workspace.get(byName: nextAutomaticWorkspaceName(projectId: projectId, monitor: monitor))
    workspace.markAsAutomaticallyNamed()
    workspace.assignProject(projectId)
    workspace.seedMonitorIfNeeded(monitor)
    return workspace
}

@MainActor
func projectWorkspaces(projectId: WorkspaceProjectId) -> [Workspace] {
    guard let project = winMuxWorkspaceState.projectsById[projectId] else { return [] }
    let indexedWorkspaces = project.workspaceOrder
        .compactMap { winMuxWorkspaceState.workspaceById[$0] }
        .filter { $0.projectId == projectId }
    if !indexedWorkspaces.isEmpty {
        return indexedWorkspaces
    }
    return Workspace.all
        .filter { $0.projectId == projectId }
        .sorted()
}

@MainActor
func orderedWorkspaces(in scope: WorkspaceScope) -> [Workspace] {
    projectWorkspaces(projectId: scope.projectId)
        .filter { !$0.isArchived }
}

@MainActor
func orderedWorkspaces(in projectId: WorkspaceProjectId) -> [Workspace] {
    projectWorkspaces(projectId: projectId)
        .filter { !$0.isArchived }
}

@MainActor
func orderedWorkspacesForPresentation() -> [Workspace] {
    var seen: Set<WorkspaceId> = []
    var result: [Workspace] = []
    for project in workspaceProjects() {
        for workspaceId in project.workspaceOrder {
            guard let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
                  !workspace.isArchived,
                  seen.insert(workspaceId).inserted
            else { continue }
            result.append(workspace)
        }
    }
    result.append(contentsOf: Workspace.all.filter { !$0.isArchived && seen.insert($0.id).inserted })
    return result
}
