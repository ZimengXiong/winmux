import AppKit
import Common

@MainActor
func workspaceProjects() -> [WorkspaceProject] {
    materializePersistedWorkspaceProjects()
    return winMuxWorkspaceState.projectsById.values.map {
        var project = $0
        project = WorkspaceProject(
            id: project.id,
            name: workspaceProjectDisplayName(project.id, fallbackName: project.name),
            workspaceOrderByLane: project.workspaceOrderByLane,
            lastActiveWorkspaceByLane: project.lastActiveWorkspaceByLane,
            linkedLaneIds: project.linkedLaneIds,
        )
        return project
    }.sorted {
        if $0.id == workspaceProjectDefaultId { return true }
        if $1.id == workspaceProjectDefaultId { return false }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
}

@MainActor
func workspaceProjectName(_ projectId: WorkspaceProjectId) -> String {
    materializePersistedWorkspaceProjects()
    return workspaceProjectDisplayName(projectId, fallbackName: winMuxWorkspaceState.projectsById[projectId]?.name ?? "Project")
}

@MainActor
func workspaceProjectDisplayName(_ projectId: WorkspaceProjectId, fallbackName: String) -> String {
    let label = config.workspaceSidebar.projectLabels[projectId.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return label.isEmpty ? fallbackName : label
}

@MainActor
func activeWorkspaceProjectId(for monitor: Monitor) -> WorkspaceProjectId {
    materializePersistedWorkspaceProjects()
    return winMuxWorkspaceState.activeProjectId(for: monitor)
}

@MainActor
func createWorkspaceProject() -> WorkspaceProject {
    materializePersistedWorkspaceProjects()
    let usedNumbers = (
        winMuxWorkspaceState.projectsById.keys.compactMap(workspaceProjectIdIndex) +
            winMuxWorkspaceState.projectsById.values.compactMap(workspaceProjectNameIndex)
    ).toSet()
    let index = lowestUnusedPositiveIndex(usedNumbers)
    let project = WorkspaceProject(id: WorkspaceProjectId("project-\(index)"), name: "Project \(index)")
    winMuxWorkspaceState.projectsById[project.id] = project
    config.workspaceSidebar.projectLabels[project.id.rawValue] = project.name
    if !isUnitTest {
        try? persistWorkspaceSidebarProjectLabel(projectId: project.id.rawValue, label: project.name)
    }
    return project
}

func workspaceProjectNameIndex(_ project: WorkspaceProject) -> Int? {
    guard project.name.hasPrefix("Project ") else { return nil }
    return Int(project.name.replacingOccurrences(of: "Project ", with: ""))
}

func workspaceProjectIdIndex(_ projectId: WorkspaceProjectId) -> Int? {
    guard projectId.rawValue.hasPrefix("project-") else { return nil }
    return Int(projectId.rawValue.replacingOccurrences(of: "project-", with: ""))
}

@MainActor
func materializePersistedWorkspaceProjects() {
    for (rawProjectId, label) in config.workspaceSidebar.projectLabels {
        let projectId = WorkspaceProjectId(rawProjectId)
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, winMuxWorkspaceState.projectsById[projectId] == nil else { continue }
        winMuxWorkspaceState.projectsById[projectId] = WorkspaceProject(id: projectId, name: name)
    }
}

@MainActor
func renameWorkspaceForSidebar(workspaceName: String, displayName: String) throws {
    guard Workspace.existing(byName: workspaceName) != nil else {
        throw WorkspaceMutationError.workspaceNotFound(workspaceName)
    }
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw WorkspaceMutationError.emptyName }

    let defaultName = workspaceDefaultDisplayName(workspaceName)
    let label = trimmedName == defaultName ? nil : trimmedName
    if let label {
        config.workspaceSidebar.workspaceLabels[workspaceName] = label
    } else {
        config.workspaceSidebar.workspaceLabels.removeValue(forKey: workspaceName)
    }
    if !isUnitTest {
        try persistWorkspaceSidebarLabel(workspaceName: workspaceName, label: label)
    }
}

@MainActor
func resetWorkspaceSidebarName(workspaceName: String) throws {
    guard Workspace.existing(byName: workspaceName) != nil else {
        throw WorkspaceMutationError.workspaceNotFound(workspaceName)
    }
    config.workspaceSidebar.workspaceLabels.removeValue(forKey: workspaceName)
    if !isUnitTest {
        try persistWorkspaceSidebarLabel(workspaceName: workspaceName, label: nil)
    }
}

@MainActor
func renameWorkspaceProject(_ projectId: WorkspaceProjectId, displayName: String) throws {
    materializePersistedWorkspaceProjects()
    guard var project = winMuxWorkspaceState.projectsById[projectId] else {
        throw WorkspaceMutationError.projectNotFound(projectId.rawValue)
    }
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw WorkspaceMutationError.emptyName }
    let duplicate = workspaceProjects().contains {
        $0.id != projectId && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
    }
    guard !duplicate else { throw WorkspaceMutationError.duplicateProjectName(trimmedName) }

    let defaultName = project.id == workspaceProjectDefaultId ? "Default" : project.name
    project = WorkspaceProject(
        id: projectId,
        name: trimmedName,
        workspaceOrderByLane: project.workspaceOrderByLane,
        lastActiveWorkspaceByLane: project.lastActiveWorkspaceByLane,
        linkedLaneIds: project.linkedLaneIds,
    )
    winMuxWorkspaceState.projectsById[projectId] = project
    let label = trimmedName == defaultName ? nil : trimmedName
    if let label {
        config.workspaceSidebar.projectLabels[projectId.rawValue] = label
    } else {
        config.workspaceSidebar.projectLabels.removeValue(forKey: projectId.rawValue)
    }
    if !isUnitTest {
        try persistWorkspaceSidebarProjectLabel(projectId: projectId.rawValue, label: label)
    }
}

@MainActor
func canDeleteWorkspaceProject(_ projectId: WorkspaceProjectId) -> Bool {
    materializePersistedWorkspaceProjects()
    return projectId != workspaceProjectDefaultId && winMuxWorkspaceState.projectsById[projectId] != nil
}

@MainActor
func workspaceProjectFallbackForDeletion(excluding projectId: WorkspaceProjectId) -> WorkspaceProjectId {
    let projects = workspaceProjects()
    guard let deletedIndex = projects.firstIndex(where: { $0.id == projectId }) else {
        return projects.first { $0.id != projectId }?.id ?? workspaceProjectDefaultId
    }
    if let next = projects.getOrNil(atIndex: deletedIndex + 1) {
        return next.id
    }
    if deletedIndex > 0 {
        return projects[deletedIndex - 1].id
    }
    return workspaceProjectDefaultId
}

@MainActor
func deleteWorkspaceForSidebar(workspaceName: String) throws {
    guard let workspace = Workspace.existing(byName: workspaceName) else {
        throw WorkspaceMutationError.workspaceNotFound(workspaceName)
    }
    try deleteWorkspace(workspace)
}

@MainActor
func deleteWorkspaceProject(_ projectId: WorkspaceProjectId) throws {
    try deleteWorkspaceProjectMovingWindowsToFallback(projectId)
}

@MainActor
func deleteWorkspaceProjectFromSidebar(_ projectId: WorkspaceProjectId) async throws {
    switch config.workspaceSidebar.projectDeletionAction {
        case .closeWindows:
            try await closeWindowsAndDeleteWorkspaceProject(projectId)
        case .moveWindowsToFallback:
            try deleteWorkspaceProjectMovingWindowsToFallback(projectId)
    }
}

@MainActor
private func deleteWorkspaceProjectMovingWindowsToFallback(_ projectId: WorkspaceProjectId) throws {
    materializePersistedWorkspaceProjects()
    guard let project = winMuxWorkspaceState.projectsById[projectId] else {
        throw WorkspaceMutationError.projectNotFound(projectId.rawValue)
    }
    guard canDeleteWorkspaceProject(projectId) else {
        throw WorkspaceMutationError.projectCannotBeDeleted(project.name)
    }

    let fallbackId = workspaceProjectFallbackForDeletion(excluding: projectId)
    let lanesShowingDeletedProject = winMuxWorkspaceState.lanesById.values.compactMap { lane -> DisplayLaneId? in
        guard let activeWorkspaceId = lane.activeWorkspaceId,
              winMuxWorkspaceState.workspaceById[activeWorkspaceId]?.projectId == projectId
        else { return nil }
        return lane.id
    }
    for laneId in lanesShowingDeletedProject {
        _ = switchWorkspaceProject(fallbackId, on: laneId.topLeftCorner.monitorApproximation)
    }

    for workspace in Workspace.all.filter({ $0.projectId == projectId }) {
        let fallback = workspaceFallbackForDeletion(
            excluding: workspace,
            projectId: fallbackId,
            monitor: workspace.workspaceMonitor,
        )
        moveWorkspaceContents(from: workspace, to: fallback)
        removeWorkspaceFromRegistry(workspace)
    }

    winMuxWorkspaceState.projectsById.removeValue(forKey: projectId)
    config.workspaceSidebar.projectLabels.removeValue(forKey: projectId.rawValue)
    config.workspaceSidebar.projectColors.removeValue(forKey: projectId.rawValue)
    if !isUnitTest {
        try persistWorkspaceSidebarProjectLabel(projectId: projectId.rawValue, label: nil)
        try persistWorkspaceSidebarProjectColor(projectId: projectId.rawValue, colorHex: nil)
    }
    checkWorkspaceHierarchyInvariants()
}

@MainActor
private func closeWindowsAndDeleteWorkspaceProject(_ projectId: WorkspaceProjectId) async throws {
    materializePersistedWorkspaceProjects()
    guard let project = winMuxWorkspaceState.projectsById[projectId] else {
        throw WorkspaceMutationError.projectNotFound(projectId.rawValue)
    }
    guard canDeleteWorkspaceProject(projectId) else {
        throw WorkspaceMutationError.projectCannotBeDeleted(project.name)
    }

    let windows = windowsInWorkspaceProject(projectId)
    if !windows.isEmpty {
        let remaining = await closeWindowsForProjectDeletion(windows)
        if !remaining.isEmpty {
            throw WorkspaceMutationError.projectCloseBlocked(project.name, remaining.count)
        }
    }

    let fallbackId = workspaceProjectFallbackForDeletion(excluding: projectId)
    let lanesShowingDeletedProject = winMuxWorkspaceState.lanesById.values.compactMap { lane -> DisplayLaneId? in
        guard let activeWorkspaceId = lane.activeWorkspaceId,
              winMuxWorkspaceState.workspaceById[activeWorkspaceId]?.projectId == projectId
        else { return nil }
        return lane.id
    }
    for laneId in lanesShowingDeletedProject {
        _ = switchWorkspaceProject(fallbackId, on: laneId.topLeftCorner.monitorApproximation)
    }

    for workspace in Workspace.all.filter({ $0.projectId == projectId }) {
        removeWorkspaceFromRegistry(workspace)
    }

    winMuxWorkspaceState.projectsById.removeValue(forKey: projectId)
    config.workspaceSidebar.projectLabels.removeValue(forKey: projectId.rawValue)
    config.workspaceSidebar.projectColors.removeValue(forKey: projectId.rawValue)
    if !isUnitTest {
        try persistWorkspaceSidebarProjectLabel(projectId: projectId.rawValue, label: nil)
        try persistWorkspaceSidebarProjectColor(projectId: projectId.rawValue, colorHex: nil)
    }
    checkWorkspaceHierarchyInvariants()
}

@MainActor
func windowsInWorkspaceProject(_ projectId: WorkspaceProjectId) -> [Window] {
    var seen: Set<UInt32> = []
    var result: [Window] = []
    for workspace in Workspace.all where workspace.projectId == projectId {
        for window in workspace.allLeafWindowsRecursive + workspaceOwnedMinimizedWindows(workspace)
        where seen.insert(window.windowId).inserted
        {
            result.append(window)
        }
    }
    return result
}

@MainActor
private func closeWindowsForProjectDeletion(_ windows: [Window]) async -> [Window] {
    var remaining: [Window] = []
    let macWindows = windows.compactMap { $0 as? MacWindow }
    let windowsByPid = Dictionary(grouping: macWindows, by: { $0.macApp.pid })
    var handledWindowIds: Set<UInt32> = []

    for (_, appWindows) in windowsByPid {
        guard let app = appWindows.first?.macApp else { continue }
        let axWindowCount = (try? await app.getAxWindowsCount()) ?? MacWindow.allWindows.count { $0.macApp === app }
        if axWindowCount == appWindows.count, app.nsApp.terminate() {
            let didTerminate = await waitForAppTermination(app)
            if didTerminate {
                for window in appWindows {
                    window.garbageCollect(skipClosedWindowsCache: true)
                    handledWindowIds.insert(window.windowId)
                }
            }
        }
    }

    for window in windows where !handledWindowIds.contains(window.windowId) {
        if let macWindow = window as? MacWindow {
            if await macWindow.requestCloseForProjectDeletion() {
                handledWindowIds.insert(window.windowId)
            } else {
                remaining.append(window)
            }
        } else {
            window.closeAxWindow()
            if window.nodeWorkspace == nil {
                handledWindowIds.insert(window.windowId)
            } else {
                remaining.append(window)
            }
        }
    }
    return remaining
}

@MainActor
private func waitForAppTermination(_ app: MacApp, timeout: TimeInterval = 2.0) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if app.nsApp.isTerminated {
            return true
        }
        if (try? await app.getAxWindowsCount()) == 0 {
            return true
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return false
}
