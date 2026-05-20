import AppKit

@MainActor
func workspaceScope(projectId: WorkspaceProjectId, monitor: Monitor) -> WorkspaceScope {
    WorkspaceScope(projectId: projectId, laneId: DisplayLaneId(monitor))
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
    let scope = WorkspaceScope(projectId: projectId, laneId: laneId)
    if let workspaceId = retainedEmptyWorkspaceId(in: scope),
       let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
       workspace != excludedWorkspace,
       isValidAssignment(workspace: workspace, screen: monitor.rect.topLeftCorner)
    {
        return workspace
    }
    if let workspace = workspaceProjectLaneWorkspaces(projectId: projectId, laneId: laneId)
        .first(where: {
            $0 != excludedWorkspace &&
                $0.isEffectivelyEmpty &&
                !$0.isArchived &&
                isValidAssignment(workspace: $0, screen: monitor.rect.topLeftCorner)
        })
    {
        return workspace
    }
    let workspace = Workspace.get(byName: nextAutomaticWorkspaceName(projectId: projectId, monitor: monitor))
    workspace.markAsAutomaticallyNamed()
    workspace.assignProject(projectId)
    workspace.assignLane(laneId)
    return workspace
}

@MainActor
func workspaceProjectLaneWorkspaces(projectId: WorkspaceProjectId, laneId: DisplayLaneId) -> [Workspace] {
    guard let project = winMuxWorkspaceState.projectsById[projectId] else { return [] }
    let indexedWorkspaces = (project.workspaceOrderByLane[laneId] ?? [])
        .compactMap { winMuxWorkspaceState.workspaceById[$0] }
        .filter { $0.projectId == projectId && $0.laneId == laneId }
    if !indexedWorkspaces.isEmpty {
        return indexedWorkspaces
    }
    return Workspace.all
        .filter { $0.projectId == projectId && $0.laneId == laneId }
        .sorted()
}

@MainActor
func orderedWorkspaces(in scope: WorkspaceScope) -> [Workspace] {
    workspaceProjectLaneWorkspaces(projectId: scope.projectId, laneId: scope.laneId)
        .filter { !$0.isArchived }
}

@MainActor
func orderedWorkspacesForPresentation() -> [Workspace] {
    var seen: Set<WorkspaceId> = []
    var result: [Workspace] = []
    for project in workspaceProjects() {
        for laneId in project.workspaceOrderByLane.keys.sorted(by: workspaceLanePresentationOrder) {
            for workspaceId in project.workspaceOrderByLane[laneId] ?? [] {
                guard let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
                      !workspace.isArchived,
                      seen.insert(workspaceId).inserted
                else { continue }
                result.append(workspace)
            }
        }
    }
    result.append(contentsOf: Workspace.all.filter { !$0.isArchived && seen.insert($0.id).inserted })
    return result
}

private func workspaceLanePresentationOrder(_ lhs: DisplayLaneId, _ rhs: DisplayLaneId) -> Bool {
    if lhs.topLeftCorner.y != rhs.topLeftCorner.y {
        return lhs.topLeftCorner.y < rhs.topLeftCorner.y
    }
    return lhs.topLeftCorner.x < rhs.topLeftCorner.x
}
