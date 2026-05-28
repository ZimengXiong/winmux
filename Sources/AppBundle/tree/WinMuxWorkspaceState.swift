import AppKit

@MainActor
struct DisplayLane {
    let id: DisplayLaneId
    var activeWorkspaceId: WorkspaceId?
    var previousWorkspaceId: WorkspaceId?
    var lastActiveWorkspaceByProject: [WorkspaceProjectId: WorkspaceId] = [:]
}

@MainActor
struct WinMuxWorkspaceState {
    var workspaceById: [WorkspaceId: Workspace] = [:]
    var workspaceIdByName: [String: WorkspaceId] = [:]
    var projectsById: [WorkspaceProjectId: WorkspaceProject] = [
        workspaceProjectDefaultId: WorkspaceProject(id: workspaceProjectDefaultId, name: "Default", order: 0),
    ]
    var lanesById: [DisplayLaneId: DisplayLane] = [:]

    private var nextWorkspaceCounter = 1
    private var nextProjectCounter = 1
    private var nextProjectOrderCounter = 1

    mutating func resetProjects(defaultProjectName: String) {
        projectsById = [
            workspaceProjectDefaultId: WorkspaceProject(id: workspaceProjectDefaultId, name: defaultProjectName, order: 0),
        ]
        nextProjectCounter = 1
        nextProjectOrderCounter = 1
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
            workspaceProjectDefaultId: WorkspaceProject(id: workspaceProjectDefaultId, name: defaultProjectName, order: 0),
        ]
        nextWorkspaceCounter = 1
        nextProjectCounter = 1
        nextProjectOrderCounter = 1
    }

    mutating func nextWorkspaceId() -> WorkspaceId {
        while workspaceById[WorkspaceId("workspace-\(nextWorkspaceCounter)")] != nil {
            nextWorkspaceCounter += 1
        }
        defer { nextWorkspaceCounter += 1 }
        return WorkspaceId("workspace-\(nextWorkspaceCounter)")
    }

    mutating func nextProjectOrder() -> Int {
        while projectsById.values.contains(where: { $0.order == nextProjectOrderCounter }) {
            nextProjectOrderCounter += 1
        }
        defer { nextProjectOrderCounter += 1 }
        return nextProjectOrderCounter
    }

    mutating func registerProject(_ project: WorkspaceProject) {
        projectsById[project.id] = project
        nextProjectOrderCounter = max(nextProjectOrderCounter, project.order + 1)
    }

    mutating func nextGeneratedProjectIdentity() -> (id: WorkspaceProjectId, name: String) {
        while projectsById[WorkspaceProjectId("project-\(nextProjectCounter)")] != nil {
            nextProjectCounter += 1
        }
        defer { nextProjectCounter += 1 }
        return (WorkspaceProjectId("project-\(nextProjectCounter)"), "Project \(nextProjectCounter)")
    }

    func workspace(named name: String) -> Workspace? {
        workspaceIdByName[name].flatMap { workspaceById[$0] }
    }

    mutating func registerWorkspace(_ workspace: Workspace) {
        workspaceById[workspace.id] = workspace
        workspaceIdByName[workspace.name] = workspace.id
        ensureProjectExists(workspace.projectId)
        insertWorkspace(workspace.id, intoProject: workspace.projectId)
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
            lane.lastActiveWorkspaceByProject = lane.lastActiveWorkspaceByProject.filter { _, id in
                id != workspace.id
            }
            lanesById[laneId] = lane
        }
        return removedLane
    }

    mutating func ensureProjectExists(_ projectId: WorkspaceProjectId) {
        if projectsById[projectId] == nil {
            let order = nextProjectOrder()
            registerProject(WorkspaceProject(id: projectId, name: "Project", order: order))
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

    func isWorkspaceActive(_ workspaceId: WorkspaceId, outside laneId: DisplayLaneId) -> Bool {
        lanesById.contains { otherLaneId, lane in
            otherLaneId != laneId && lane.activeWorkspaceId == workspaceId
        }
    }

    mutating func setActiveWorkspace(_ workspace: Workspace, on laneId: DisplayLaneId) -> Bool {
        ensureLaneExists(laneId)
        ensureProjectExists(workspace.projectId)

        var lane = lanesById[laneId] ?? DisplayLane(id: laneId)
        if lane.activeWorkspaceId != workspace.id {
            lane.previousWorkspaceId = lane.activeWorkspaceId
        }
        lane.activeWorkspaceId = workspace.id
        lane.lastActiveWorkspaceByProject[workspace.projectId] = workspace.id
        lanesById[laneId] = lane
        return true
    }

    mutating func assignWorkspace(_ workspace: Workspace, to projectId: WorkspaceProjectId) {
        ensureProjectExists(projectId)
        removeWorkspaceFromProjectIndexes(workspace.id)
        workspace.projectId = projectId
        insertWorkspace(workspace.id, intoProject: projectId)
    }

    mutating func pruneProjectWorkspaceIndexes() {
        for workspace in workspaceById.values {
            ensureProjectExists(workspace.projectId)
        }
        for (laneId, lane) in lanesById {
            var lane = lane
            if lane.activeWorkspaceId.flatMap({ workspaceById[$0] }) == nil {
                lane.activeWorkspaceId = nil
            }
            if lane.previousWorkspaceId.flatMap({ workspaceById[$0] }) == nil {
                lane.previousWorkspaceId = nil
            }
            lane.lastActiveWorkspaceByProject = lane.lastActiveWorkspaceByProject.filter { projectId, workspaceId in
                workspaceById[workspaceId]?.projectId == projectId
            }
            lanesById[laneId] = lane
        }

        let orderedWorkspaces = workspaceById.values.sorted()
        for (projectId, project) in projectsById {
            var project = project
            var seen: Set<WorkspaceId> = []
            project.workspaceOrder = project.workspaceOrder.filter { workspaceId in
                guard let workspace = workspaceById[workspaceId],
                      workspace.projectId == projectId,
                      !seen.contains(workspaceId)
                else {
                    return false
                }
                seen.insert(workspaceId)
                return true
            }
            for workspace in orderedWorkspaces where workspace.projectId == projectId && !seen.contains(workspace.id) {
                project.workspaceOrder.append(workspace.id)
                seen.insert(workspace.id)
            }
            projectsById[projectId] = project
        }
    }

    private mutating func rebuildProjectWorkspaceIndexes() {
        for (projectId, project) in projectsById {
            var project = project
            project.workspaceOrder = []
            projectsById[projectId] = project
        }
        for workspace in workspaceById.values.sorted() {
            ensureProjectExists(workspace.projectId)
            insertWorkspace(workspace.id, intoProject: workspace.projectId)
        }
        for (laneId, lane) in lanesById {
            guard let workspaceId = lane.activeWorkspaceId,
                  let workspace = workspaceById[workspaceId]
            else { continue }
            var lane = lane
            lane.lastActiveWorkspaceByProject[workspace.projectId] = workspaceId
            lanesById[laneId] = lane
        }
    }

    private mutating func insertWorkspace(_ workspaceId: WorkspaceId, intoProject projectId: WorkspaceProjectId) {
        var project = projectsById[projectId].orDie()
        if !project.workspaceOrder.contains(workspaceId) {
            project.workspaceOrder.append(workspaceId)
        }
        projectsById[projectId] = project
    }

    private mutating func removeWorkspaceFromProjectIndexes(_ workspaceId: WorkspaceId) {
        for (projectId, project) in projectsById {
            var project = project
            project.workspaceOrder = project.workspaceOrder.filter { $0 != workspaceId }
            projectsById[projectId] = project
        }
    }
}

@MainActor var winMuxWorkspaceState = WinMuxWorkspaceState()
