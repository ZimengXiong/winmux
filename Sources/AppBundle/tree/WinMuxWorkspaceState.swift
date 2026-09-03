import AppKit

@MainActor
struct MonitorViewport {
    let id: MonitorViewportId
    var activeWorkspaceId: WorkspaceId?
    var previousWorkspaceId: WorkspaceId?
    var lastActiveWorkspaceByProject: [WorkspaceProjectId: WorkspaceId] = [:]
}

@MainActor
struct WinMuxWorkspaceState {
    var workspaceById: [WorkspaceId: Workspace] = [:] {
        didSet { sortedWorkspacesCache = nil }
    }
    /// Workspace.all is read dozens of times per refresh session and sorting by logical name
    /// segments isn't free. The sort key (nameLogicalSegments) is immutable per Workspace
    /// object — renames create new workspaces — so the order can only change when the registry
    /// dictionary itself changes.
    private var sortedWorkspacesCache: [Workspace]? = nil
    var workspaceIdByName: [String: WorkspaceId] = [:]

    mutating func sortedWorkspaces() -> [Workspace] {
        if let cached = sortedWorkspacesCache { return cached }
        let sorted = workspaceById.values.sorted()
        sortedWorkspacesCache = sorted
        return sorted
    }
    var projectsById: [WorkspaceProjectId: WorkspaceProject] = [
        workspaceProjectDefaultId: WorkspaceProject(id: workspaceProjectDefaultId, name: "Default", order: 0),
    ]
    var monitorViewportsById: [MonitorViewportId: MonitorViewport] = [:]

    private var nextWorkspaceCounter = 1
    private var nextProjectOrderCounter = 1

    mutating func resetProjects(defaultProjectName: String) {
        projectsById = [
            workspaceProjectDefaultId: WorkspaceProject(id: workspaceProjectDefaultId, name: defaultProjectName, order: 0),
        ]
        nextProjectOrderCounter = 1
        for workspace in workspaceById.values {
            workspace.projectId = workspaceProjectDefaultId
        }
        rebuildProjectWorkspaceIndexes()
    }

    mutating func resetDisplayAssignments() {
        monitorViewportsById = [:]
    }

    mutating func resetWorkspaceRegistryForTests(defaultProjectName: String) {
        workspaceById = [:]
        workspaceIdByName = [:]
        monitorViewportsById = [:]
        projectsById = [
            workspaceProjectDefaultId: WorkspaceProject(id: workspaceProjectDefaultId, name: defaultProjectName, order: 0),
        ]
        nextWorkspaceCounter = 1
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

    func nextGeneratedProjectIdentity() -> (id: WorkspaceProjectId, name: String) {
        while true {
            let id = WorkspaceProjectId("project-\(UUID().uuidString.lowercased())")
            if projectsById[id] == nil {
                return (id, "Project")
            }
        }
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

    mutating func removeWorkspace(_ workspace: Workspace) -> MonitorViewportId? {
        workspaceById.removeValue(forKey: workspace.id)
        workspaceIdByName.removeValue(forKey: workspace.name)
        removeWorkspaceFromProjectIndexes(workspace.id)

        var removedViewport: MonitorViewportId?
        for (viewportId, viewport) in monitorViewportsById {
            var viewport = viewport
            if viewport.activeWorkspaceId == workspace.id {
                viewport.activeWorkspaceId = nil
                removedViewport = viewportId
            }
            if viewport.previousWorkspaceId == workspace.id {
                viewport.previousWorkspaceId = nil
            }
            viewport.lastActiveWorkspaceByProject = viewport.lastActiveWorkspaceByProject.filter { _, id in
                id != workspace.id
            }
            monitorViewportsById[viewportId] = viewport
        }
        return removedViewport
    }

    mutating func ensureProjectExists(_ projectId: WorkspaceProjectId) {
        if projectsById[projectId] == nil {
            let order = nextProjectOrder()
            registerProject(WorkspaceProject(id: projectId, name: "Project", order: order))
        }
    }

    mutating func ensureMonitorViewportExists(_ viewportId: MonitorViewportId) {
        if monitorViewportsById[viewportId] == nil {
            monitorViewportsById[viewportId] = MonitorViewport(id: viewportId)
        }
    }

    mutating func activeProjectId(for monitor: Monitor) -> WorkspaceProjectId {
        let viewportId = MonitorViewportId(monitor)
        ensureMonitorViewportExists(viewportId)
        return monitorViewportsById[viewportId]?.activeWorkspaceId.flatMap { workspaceById[$0]?.projectId } ?? workspaceProjectDefaultId
    }

    mutating func visibleWorkspace(for monitor: Monitor) -> Workspace? {
        let viewportId = MonitorViewportId(monitor)
        ensureMonitorViewportExists(viewportId)
        return monitorViewportsById[viewportId]?.activeWorkspaceId.flatMap { workspaceById[$0] }
    }

    func isWorkspaceActive(_ workspaceId: WorkspaceId, outside viewportId: MonitorViewportId) -> Bool {
        monitorViewportsById.contains { otherViewportId, viewport in
            otherViewportId != viewportId && viewport.activeWorkspaceId == workspaceId
        }
    }

    mutating func setActiveWorkspace(_ workspace: Workspace, on viewportId: MonitorViewportId) -> Bool {
        ensureMonitorViewportExists(viewportId)
        ensureProjectExists(workspace.projectId)

        var viewport = monitorViewportsById[viewportId] ?? MonitorViewport(id: viewportId)
        if viewport.activeWorkspaceId != workspace.id {
            viewport.previousWorkspaceId = viewport.activeWorkspaceId
        }
        viewport.activeWorkspaceId = workspace.id
        viewport.lastActiveWorkspaceByProject[workspace.projectId] = workspace.id
        monitorViewportsById[viewportId] = viewport
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
        for (viewportId, viewport) in monitorViewportsById {
            var viewport = viewport
            if viewport.activeWorkspaceId.flatMap({ workspaceById[$0] }) == nil {
                viewport.activeWorkspaceId = nil
            }
            if viewport.previousWorkspaceId.flatMap({ workspaceById[$0] }) == nil {
                viewport.previousWorkspaceId = nil
            }
            viewport.lastActiveWorkspaceByProject = viewport.lastActiveWorkspaceByProject.filter { projectId, workspaceId in
                workspaceById[workspaceId]?.projectId == projectId
            }
            monitorViewportsById[viewportId] = viewport
        }

        let orderedWorkspaces = sortedWorkspaces()
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
        for workspace in sortedWorkspaces() {
            ensureProjectExists(workspace.projectId)
            insertWorkspace(workspace.id, intoProject: workspace.projectId)
        }
        for (viewportId, viewport) in monitorViewportsById {
            guard let workspaceId = viewport.activeWorkspaceId,
                  let workspace = workspaceById[workspaceId]
            else { continue }
            var viewport = viewport
            viewport.lastActiveWorkspaceByProject[workspace.projectId] = workspaceId
            monitorViewportsById[viewportId] = viewport
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
