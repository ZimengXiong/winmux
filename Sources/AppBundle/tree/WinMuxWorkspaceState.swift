import AppKit

@MainActor
struct DisplayLane {
    let id: DisplayLaneId
    var activeWorkspaceId: WorkspaceId?
    var previousWorkspaceId: WorkspaceId?
}

@MainActor
struct WinMuxWorkspaceState {
    var workspaceById: [WorkspaceId: Workspace] = [:]
    var workspaceIdByName: [String: WorkspaceId] = [:]
    var projectsById: [WorkspaceProjectId: WorkspaceProject] = [
        workspaceProjectDefaultId: WorkspaceProject(id: workspaceProjectDefaultId, name: "Default"),
    ]
    var lanesById: [DisplayLaneId: DisplayLane] = [:]

    private var nextWorkspaceCounter = 1

    mutating func resetProjects(defaultProjectName: String) {
        projectsById = [
            workspaceProjectDefaultId: WorkspaceProject(id: workspaceProjectDefaultId, name: defaultProjectName),
        ]
        for workspace in workspaceById.values {
            workspace.projectId = workspaceProjectDefaultId
        }
        rebuildProjectWorkspaceIndexes()
    }

    mutating func resetDisplayAssignments() {
        lanesById = [:]
    }

    mutating func resetWorkspaceRegistryForTests(defaultProjectName: String) {
        workspaceById = [:]
        workspaceIdByName = [:]
        lanesById = [:]
        projectsById = [
            workspaceProjectDefaultId: WorkspaceProject(id: workspaceProjectDefaultId, name: defaultProjectName),
        ]
        nextWorkspaceCounter = 1
    }

    mutating func nextWorkspaceId() -> WorkspaceId {
        while workspaceById[WorkspaceId("workspace-\(nextWorkspaceCounter)")] != nil {
            nextWorkspaceCounter += 1
        }
        defer { nextWorkspaceCounter += 1 }
        return WorkspaceId("workspace-\(nextWorkspaceCounter)")
    }

    func workspace(named name: String) -> Workspace? {
        workspaceIdByName[name].flatMap { workspaceById[$0] }
    }

    mutating func registerWorkspace(_ workspace: Workspace) {
        workspaceById[workspace.id] = workspace
        workspaceIdByName[workspace.name] = workspace.id
        ensureProjectExists(workspace.projectId)
        ensureLaneExists(workspace.laneId)
        insertWorkspace(workspace.id, intoProject: workspace.projectId, laneId: workspace.laneId)
    }

    mutating func removeWorkspace(_ workspace: Workspace) -> DisplayLaneId? {
        workspaceById.removeValue(forKey: workspace.id)
        workspaceIdByName.removeValue(forKey: workspace.name)
        removeWorkspaceFromProjectIndexes(workspace.id)

        var removedLane: DisplayLaneId?
        for (laneId, lane) in lanesById {
            var lane = lane
            if lane.activeWorkspaceId == workspace.id {
                lane.activeWorkspaceId = nil
                removedLane = laneId
            }
            if lane.previousWorkspaceId == workspace.id {
                lane.previousWorkspaceId = nil
            }
            lanesById[laneId] = lane
        }
        return removedLane
    }

    mutating func ensureProjectExists(_ projectId: WorkspaceProjectId) {
        if projectsById[projectId] == nil {
            projectsById[projectId] = WorkspaceProject(id: projectId, name: "Project")
        }
    }

    mutating func ensureLaneExists(_ laneId: DisplayLaneId) {
        if lanesById[laneId] == nil {
            lanesById[laneId] = DisplayLane(id: laneId)
        }
    }

    mutating func activeProjectId(for monitor: Monitor) -> WorkspaceProjectId {
        let laneId = DisplayLaneId(monitor)
        ensureLaneExists(laneId)
        return lanesById[laneId]?.activeWorkspaceId.flatMap { workspaceById[$0]?.projectId } ?? workspaceProjectDefaultId
    }

    mutating func visibleWorkspace(for monitor: Monitor) -> Workspace? {
        let laneId = DisplayLaneId(monitor)
        ensureLaneExists(laneId)
        return lanesById[laneId]?.activeWorkspaceId.flatMap { workspaceById[$0] }
    }

    mutating func setActiveWorkspace(_ workspace: Workspace, on laneId: DisplayLaneId) -> Bool {
        ensureLaneExists(laneId)
        ensureProjectExists(workspace.projectId)
        if workspace.laneId != laneId {
            moveWorkspace(workspace, to: laneId)
        }

        for (otherLaneId, otherLane) in lanesById where otherLane.activeWorkspaceId == workspace.id && otherLaneId != laneId {
            var otherLane = otherLane
            otherLane.previousWorkspaceId = workspace.id
            otherLane.activeWorkspaceId = nil
            lanesById[otherLaneId] = otherLane
        }

        var lane = lanesById[laneId] ?? DisplayLane(id: laneId)
        if lane.activeWorkspaceId != workspace.id {
            lane.previousWorkspaceId = lane.activeWorkspaceId
        }
        lane.activeWorkspaceId = workspace.id
        lanesById[laneId] = lane

        var project = projectsById[workspace.projectId].orDie()
        project.lastActiveWorkspaceByLane[laneId] = workspace.id
        projectsById[project.id] = project
        return true
    }

    mutating func moveWorkspace(_ workspace: Workspace, to laneId: DisplayLaneId) {
        ensureLaneExists(laneId)
        removeWorkspaceFromProjectIndexes(workspace.id)
        workspace.laneId = laneId
        insertWorkspace(workspace.id, intoProject: workspace.projectId, laneId: laneId)
    }

    mutating func assignWorkspace(_ workspace: Workspace, to projectId: WorkspaceProjectId) {
        ensureProjectExists(projectId)
        removeWorkspaceFromProjectIndexes(workspace.id)
        workspace.projectId = projectId
        insertWorkspace(workspace.id, intoProject: projectId, laneId: workspace.laneId)
    }

    mutating func pruneProjectWorkspaceIndexes() {
        for (projectId, project) in projectsById {
            var project = project
            project.workspaceOrderByLane = project.workspaceOrderByLane.mapValues { ids in
                ids.filter { workspaceById[$0]?.projectId == projectId }
            }.filter { !$0.value.isEmpty }
            project.lastActiveWorkspaceByLane = project.lastActiveWorkspaceByLane.filter { laneId, workspaceId in
                workspaceById[workspaceId]?.projectId == projectId &&
                    workspaceById[workspaceId]?.laneId == laneId
            }
            projectsById[projectId] = project
        }
    }

    private mutating func rebuildProjectWorkspaceIndexes() {
        for (projectId, project) in projectsById {
            var project = project
            project.workspaceOrderByLane = [:]
            project.lastActiveWorkspaceByLane = [:]
            projectsById[projectId] = project
        }
        for workspace in workspaceById.values.sorted() {
            ensureProjectExists(workspace.projectId)
            insertWorkspace(workspace.id, intoProject: workspace.projectId, laneId: workspace.laneId)
        }
        for (laneId, lane) in lanesById {
            guard let workspaceId = lane.activeWorkspaceId,
                  let workspace = workspaceById[workspaceId]
            else { continue }
            var project = projectsById[workspace.projectId].orDie()
            project.lastActiveWorkspaceByLane[laneId] = workspaceId
            projectsById[project.id] = project
        }
    }

    private mutating func insertWorkspace(_ workspaceId: WorkspaceId, intoProject projectId: WorkspaceProjectId, laneId: DisplayLaneId) {
        var project = projectsById[projectId].orDie()
        var order = project.workspaceOrderByLane[laneId] ?? []
        if !order.contains(workspaceId) {
            order.append(workspaceId)
        }
        project.workspaceOrderByLane[laneId] = order
        projectsById[projectId] = project
    }

    private mutating func removeWorkspaceFromProjectIndexes(_ workspaceId: WorkspaceId) {
        for (projectId, project) in projectsById {
            var project = project
            project.workspaceOrderByLane = project.workspaceOrderByLane.mapValues { ids in
                ids.filter { $0 != workspaceId }
            }.filter { !$0.value.isEmpty }
            project.lastActiveWorkspaceByLane = project.lastActiveWorkspaceByLane.filter { _, id in
                id != workspaceId
            }
            projectsById[projectId] = project
        }
    }
}

@MainActor var winMuxWorkspaceState = WinMuxWorkspaceState()
