import AppKit
import Common

@MainActor
func workspaceProjects() -> [WorkspaceProject] {
    materializePersistedWorkspaceProjects()
    ensureMinimumWorkspaceForAllProjects()
    let projects = winMuxWorkspaceState.projectsById.values.sorted {
        if $0.id == workspaceProjectDefaultId { return true }
        if $1.id == workspaceProjectDefaultId { return false }
        return workspaceProjectOrderPrecedes($0, $1)
    }
    var numberedProjectIndex = 0
    return projects.map { project in
        let displayName: String
        if let configuredName = config.workspaceSidebar.projectLabels[project.id.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredName.isEmpty,
           configuredName != project.id.rawValue
        {
            displayName = configuredName
        } else if project.id == workspaceProjectDefaultId {
            displayName = "Default"
        } else {
            numberedProjectIndex += 1
            displayName = "Project \(numberedProjectIndex)"
        }
        return WorkspaceProject(
            id: project.id,
            name: displayName,
            order: project.order,
            workspaceOrder: project.workspaceOrder,
            linkedViewportIds: project.linkedViewportIds,
        )
    }
}

@MainActor
func workspaceProjectName(_ projectId: WorkspaceProjectId) -> String {
    workspaceProjects().first { $0.id == projectId }?.name ?? "Project"
}

@MainActor
func workspaceProject(id rawId: String) -> WorkspaceProject? {
    workspaceProjects().first { $0.id.rawValue == rawId }
}

@MainActor
func workspaceProjectDisplayName(_ projectId: WorkspaceProjectId, fallbackName: String) -> String {
    workspaceProjects().first { $0.id == projectId }?.name ?? fallbackName
}

@MainActor
func activeWorkspaceProjectId(for monitor: Monitor) -> WorkspaceProjectId {
    materializePersistedWorkspaceProjects()
    return winMuxWorkspaceState.activeProjectId(for: monitor)
}

@MainActor
func createWorkspaceProject() -> WorkspaceProject {
    materializePersistedWorkspaceProjects()
    let identity = winMuxWorkspaceState.nextGeneratedProjectIdentity()
    let order = winMuxWorkspaceState.nextProjectOrder()
    let project = WorkspaceProject(id: identity.id, name: identity.name, order: order)
    winMuxWorkspaceState.registerProject(project)
    ensureMinimumWorkspace(for: project.id)
    config.workspaceSidebar.projectLabels[project.id.rawValue] = project.id.rawValue
    if !isUnitTest {
        try? persistWorkspaceSidebarProjectLabel(projectId: project.id.rawValue, label: project.id.rawValue)
    }
    return project
}

@MainActor
func createWorkspaceProjectForCommand(displayName: String?, colorHex: String?) throws -> WorkspaceProject {
    materializePersistedWorkspaceProjects()
    let trimmedName = try displayName.map(normalizedWorkspaceProjectDisplayName)
    let normalizedColor: String?
    if let colorHex {
        guard let normalized = normalizedWorkspaceSidebarColorHex(colorHex) else {
            throw WorkspaceMutationError.invalidProjectColor(colorHex)
        }
        normalizedColor = normalized
    } else {
        normalizedColor = nil
    }

    let identity = winMuxWorkspaceState.nextGeneratedProjectIdentity()
    let label = trimmedName ?? identity.id.rawValue
    if !isUnitTest {
        try persistWorkspaceSidebarProjectMetadata(
            projectId: identity.id.rawValue,
            label: label,
            colorHex: normalizedColor,
        )
    }

    let project = WorkspaceProject(
        id: identity.id,
        name: identity.name,
        order: winMuxWorkspaceState.nextProjectOrder(),
    )
    winMuxWorkspaceState.registerProject(project)
    ensureMinimumWorkspace(for: project.id)
    config.workspaceSidebar.projectLabels[project.id.rawValue] = label
    if let normalizedColor {
        config.workspaceSidebar.projectColors[project.id.rawValue] = normalizedColor
    }
    return project
}

func workspaceProjectOrderPrecedes(_ lhs: WorkspaceProject, _ rhs: WorkspaceProject) -> Bool {
    if lhs.order != rhs.order {
        return lhs.order < rhs.order
    }
    return lhs.id < rhs.id
}

@MainActor
func materializePersistedWorkspaceProjects() {
    for (rawProjectId, label) in config.workspaceSidebar.projectLabels {
        let projectId = WorkspaceProjectId(rawProjectId)
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, winMuxWorkspaceState.projectsById[projectId] == nil else { continue }
        let order = winMuxWorkspaceState.nextProjectOrder()
        winMuxWorkspaceState.registerProject(WorkspaceProject(id: projectId, name: name, order: order))
    }
    ensureMinimumWorkspaceForAllProjects()
}

@MainActor
func ensureMinimumWorkspaceForAllProjects(monitor: Monitor = mainMonitor) {
    for projectId in winMuxWorkspaceState.projectsById.keys {
        ensureMinimumWorkspace(for: projectId, monitor: monitor)
    }
}

@MainActor
func ensureMinimumWorkspace(for projectId: WorkspaceProjectId, monitor: Monitor = mainMonitor) {
    guard winMuxWorkspaceState.projectsById[projectId] != nil else { return }
    guard !Workspace.all.contains(where: { $0.projectId == projectId && !$0.isArchived }) else { return }
    _ = createBlankWorkspace(projectId: projectId, monitor: monitor)
}

@MainActor
func renameWorkspaceForSidebar(workspaceName: String, displayName: String) throws {
    guard Workspace.existing(byName: workspaceName) != nil else {
        throw WorkspaceMutationError.workspaceNotFound(workspaceName)
    }
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
        throw WorkspaceMutationError.emptyName
    }
    if trimmedName == workspaceDefaultDisplayName(workspaceName) {
        try resetWorkspaceSidebarName(workspaceName: workspaceName)
        return
    }
    config.workspaceSidebar.workspaceLabels[workspaceName] = trimmedName
    if !isUnitTest {
        try persistWorkspaceSidebarLabel(workspaceName: workspaceName, label: trimmedName)
    }
}

func normalizedWorkspaceProjectDisplayName(_ raw: String) throws -> String {
    guard !raw.unicodeScalars.contains(where: { scalar in
        scalar.value <= 0x1F || (0x7F ... 0x9F).contains(scalar.value)
    }) else {
        throw WorkspaceMutationError.nameContainsControlCharacters
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw WorkspaceMutationError.emptyName
    }
    return trimmed
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
    guard winMuxWorkspaceState.projectsById[projectId] != nil else {
        throw WorkspaceMutationError.projectNotFound(projectId.rawValue)
    }
    let trimmedName = try normalizedWorkspaceProjectDisplayName(displayName)
    if !isUnitTest {
        try persistWorkspaceSidebarProjectLabel(projectId: projectId.rawValue, label: trimmedName)
    }
    config.workspaceSidebar.projectLabels[projectId.rawValue] = trimmedName
}

@MainActor
@discardableResult
func setWorkspaceProjectColor(_ projectId: WorkspaceProjectId, colorHex: String?) throws -> String? {
    materializePersistedWorkspaceProjects()
    guard winMuxWorkspaceState.projectsById[projectId] != nil else {
        throw WorkspaceMutationError.projectNotFound(projectId.rawValue)
    }
    let normalizedColorHex: String?
    if let colorHex {
        guard let normalized = normalizedWorkspaceSidebarColorHex(colorHex) else {
            throw WorkspaceMutationError.invalidProjectColor(colorHex)
        }
        normalizedColorHex = normalized
    } else {
        normalizedColorHex = nil
    }
    if !isUnitTest {
        try persistWorkspaceSidebarProjectColor(projectId: projectId.rawValue, colorHex: normalizedColorHex)
    }
    if let normalizedColorHex {
        config.workspaceSidebar.projectColors[projectId.rawValue] = normalizedColorHex
    } else {
        config.workspaceSidebar.projectColors.removeValue(forKey: projectId.rawValue)
    }
    return normalizedColorHex
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
func deleteWorkspaceProject(
    _ projectId: WorkspaceProjectId,
    action: WorkspaceProjectDeletionAction,
) async throws {
    switch action {
        case .closeWindows:
            try await closeWindowsAndDeleteWorkspaceProject(projectId)
        case .moveWindowsToFallback:
            try deleteWorkspaceProjectMovingWindowsToFallback(projectId)
    }
}

@MainActor
func deleteWorkspaceProjectFromSidebar(_ projectId: WorkspaceProjectId) async throws {
    try await deleteWorkspaceProject(projectId, action: config.workspaceSidebar.projectDeletionAction)
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

    try persistWorkspaceSidebarProjectMetadataRemoval(projectId)
    removeWorkspaceSidebarProjectMetadataFromMemory(projectId)

    let fallbackId = workspaceProjectFallbackForDeletion(excluding: projectId)
    let viewportsShowingDeletedProject = winMuxWorkspaceState.monitorViewportsById.values.compactMap { viewport -> MonitorViewportId? in
        guard let activeWorkspaceId = viewport.activeWorkspaceId,
              winMuxWorkspaceState.workspaceById[activeWorkspaceId]?.projectId == projectId
        else { return nil }
        return viewport.id
    }
    for viewportId in viewportsShowingDeletedProject {
        _ = switchWorkspaceProject(fallbackId, on: viewportId.topLeftCorner.monitorApproximation)
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
    ensureVisibleActiveProjectWorkspaces()
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
    let viewportsShowingDeletedProject = winMuxWorkspaceState.monitorViewportsById.values.compactMap { viewport -> MonitorViewportId? in
        guard let activeWorkspaceId = viewport.activeWorkspaceId,
              winMuxWorkspaceState.workspaceById[activeWorkspaceId]?.projectId == projectId
        else { return nil }
        return viewport.id
    }
    for viewportId in viewportsShowingDeletedProject {
        _ = switchWorkspaceProject(fallbackId, on: viewportId.topLeftCorner.monitorApproximation)
    }

    for workspace in Workspace.all.filter({ $0.projectId == projectId }) {
        removeWorkspaceFromRegistry(workspace)
    }

    winMuxWorkspaceState.projectsById.removeValue(forKey: projectId)
    try clearWorkspaceSidebarProjectMetadata(projectId)
    ensureVisibleActiveProjectWorkspaces()
    checkWorkspaceHierarchyInvariants()
}

@MainActor
private func clearWorkspaceSidebarProjectMetadata(_ projectId: WorkspaceProjectId) throws {
    try persistWorkspaceSidebarProjectMetadataRemoval(projectId)
    removeWorkspaceSidebarProjectMetadataFromMemory(projectId)
}

@MainActor
private func persistWorkspaceSidebarProjectMetadataRemoval(_ projectId: WorkspaceProjectId) throws {
    guard !isUnitTest else { return }
    try persistWorkspaceSidebarProjectMetadata(
        projectId: projectId.rawValue,
        label: nil,
        colorHex: nil,
    )
}

@MainActor
private func removeWorkspaceSidebarProjectMetadataFromMemory(_ projectId: WorkspaceProjectId) {
    config.workspaceSidebar.projectLabels.removeValue(forKey: projectId.rawValue)
    config.workspaceSidebar.projectColors.removeValue(forKey: projectId.rawValue)
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
