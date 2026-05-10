import AppKit
import Common

private let sidebarDraftWorkspacePrefix = "__sidebar_draft_workspace_"
private let internalAutomaticWorkspacePrefix = "__internal_auto_workspace_"
let workspaceProjectDefaultId = WorkspaceProjectId.defaultProject

struct WorkspaceProject: Hashable, Identifiable {
    let id: WorkspaceProjectId
    let name: String
    var workspaceOrderByLane: [DisplayLaneId: [WorkspaceId]] = [:]
    var lastActiveWorkspaceByLane: [DisplayLaneId: WorkspaceId] = [:]
    var linkedLaneIds: Set<DisplayLaneId> = []
}

enum WorkspaceMutationError: LocalizedError {
    case workspaceNotFound(String)
    case workspaceCannotBeDeleted(String)
    case projectNotFound(String)
    case projectCannotBeDeleted(String)
    case emptyName
    case duplicateProjectName(String)

    var errorDescription: String? {
        switch self {
            case .workspaceNotFound(let name):
                "Workspace '\(name)' no longer exists."
            case .workspaceCannotBeDeleted(let name):
                "Workspace '\(name)' cannot be deleted."
            case .projectNotFound(let id):
                "Project '\(id)' no longer exists."
            case .projectCannotBeDeleted(let name):
                "Project '\(name)' cannot be deleted."
            case .emptyName:
                "Name cannot be empty."
            case .duplicateProjectName(let name):
                "A project named '\(name)' already exists."
        }
    }
}

enum WorkspaceNamingStyle: String, Codable, Sendable {
    case explicit
    case automatic
}

private func automaticWorkspaceIndex(_ name: String) -> Int? {
    Int(name)
}

private func internalAutomaticWorkspaceIndex(_ name: String) -> Int? {
    guard name.hasPrefix(internalAutomaticWorkspacePrefix) else { return nil }
    let suffix = name.replacingOccurrences(of: internalAutomaticWorkspacePrefix, with: "")
    return Int(suffix)
}

private func lowestUnusedPositiveIndex(_ usedIndices: Set<Int>) -> Int {
    var candidate = 1
    while usedIndices.contains(candidate) {
        candidate += 1
    }
    return candidate
}

@MainActor
func workspaceScope(projectId: WorkspaceProjectId, monitor: Monitor) -> WorkspaceScope {
    WorkspaceScope(projectId: projectId, laneId: DisplayLaneId(monitor))
}

@MainActor func getOrCreateLaneFallbackWorkspace(for monitor: Monitor) -> Workspace {
    getOrCreateFallbackWorkspace(
        projectId: activeWorkspaceProjectId(for: monitor),
        laneId: DisplayLaneId(monitor),
        monitor: monitor,
    )
}

@MainActor
private func getOrCreateLaneFallbackWorkspace(forPoint point: CGPoint) -> Workspace {
    let monitor = point.monitorApproximation
    return getOrCreateFallbackWorkspace(
        projectId: activeWorkspaceProjectId(for: monitor),
        laneId: DisplayLaneId(topLeftCorner: point),
        monitor: monitor,
    )
}

@MainActor
private func getOrCreateFallbackWorkspace(
    projectId: WorkspaceProjectId,
    laneId: DisplayLaneId,
    monitor: Monitor,
) -> Workspace {
    let scope = WorkspaceScope(projectId: projectId, laneId: laneId)
    if let workspaceId = retainedEmptyWorkspaceId(in: scope),
       let workspace = winMuxWorkspaceState.workspaceById[workspaceId]
    {
        return workspace
    }
    if let workspace = workspaceProjectLaneWorkspaces(projectId: projectId, laneId: laneId)
        .first(where: { $0.isEffectivelyEmpty && !$0.isArchived })
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
private func workspaceProjectLaneWorkspaces(projectId: WorkspaceProjectId, laneId: DisplayLaneId) -> [Workspace] {
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
private func orderedWorkspaces(in scope: WorkspaceScope) -> [Workspace] {
    workspaceProjectLaneWorkspaces(projectId: scope.projectId, laneId: scope.laneId)
        .filter { !$0.isArchived }
}

@MainActor
func orderedWorkspacesForPresentation() -> [Workspace] {
    var seen: Set<WorkspaceId> = []
    var result: [Workspace] = []
    for project in workspaceProjects() {
        let laneIds = project.workspaceOrderByLane.keys.sorted {
            if $0.topLeftCorner.y != $1.topLeftCorner.y {
                return $0.topLeftCorner.y < $1.topLeftCorner.y
            }
            return $0.topLeftCorner.x < $1.topLeftCorner.x
        }
        for laneId in laneIds {
            for workspaceId in project.workspaceOrderByLane[laneId] ?? [] {
                guard let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
                      !workspace.isArchived,
                      seen.insert(workspaceId).inserted
                else { continue }
                result.append(workspace)
            }
        }
    }
    result.append(contentsOf: Workspace.all.filter { seen.insert($0.id).inserted })
    return result
}

@MainActor
func orderedUserFacingWorkspaces(in scope: WorkspaceScope, focusedWorkspace: Workspace? = nil) -> [Workspace] {
    userFacingWorkspaces(orderedWorkspaces(in: scope), focusedWorkspace: focusedWorkspace)
}

@MainActor
private func nextInternalAutomaticWorkspaceName() -> String {
    let usedIndices = Set(winMuxWorkspaceState.workspaceIdByName.keys.compactMap(internalAutomaticWorkspaceIndex))
    var candidate = 1
    while usedIndices.contains(candidate) {
        candidate += 1
    }
    return "\(internalAutomaticWorkspacePrefix)\(candidate)"
}

@MainActor
private func nextAutomaticWorkspaceDisplayIndex(projectId: WorkspaceProjectId, monitor: Monitor) -> Int {
    let usedIndices = orderedUserFacingWorkspaces(
        in: workspaceScope(projectId: projectId, monitor: monitor),
        focusedWorkspace: nil,
    )
        .filter(\.usesAutomaticDisplayName)
        .compactMap { automaticWorkspaceDisplayIndex($0, focusedWorkspace: nil) }
        .toSet()
    return lowestUnusedPositiveIndex(usedIndices)
}

@MainActor
private func nextAutomaticWorkspaceName(projectId _: WorkspaceProjectId = workspaceProjectDefaultId, monitor _: Monitor = mainMonitor) -> String {
    let usedNumericRawNames = Set(winMuxWorkspaceState.workspaceIdByName.keys.compactMap(parsePositiveWorkspaceDisplayIndex))
    let preferredRawName = String(lowestUnusedPositiveIndex(usedNumericRawNames))
    if winMuxWorkspaceState.workspaceIdByName[preferredRawName] == nil {
        return preferredRawName
    }
    return nextInternalAutomaticWorkspaceName()
}

@MainActor
func nextSidebarDraftWorkspaceName() -> String {
    clearOrphanedSidebarDraftWorkspaceLabels()
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
private func clearWorkspaceSidebarLabelIfNeeded(_ workspaceName: String) {
    guard config.workspaceSidebar.workspaceLabels.removeValue(forKey: workspaceName) != nil else { return }
    if !isUnitTest {
        try? persistWorkspaceSidebarLabel(workspaceName: workspaceName, label: nil)
    }
}

@MainActor
private func clearSidebarDraftWorkspaceLabelIfNeeded(_ workspaceName: String) {
    guard isSidebarDraftWorkspaceName(workspaceName) else { return }
    clearWorkspaceSidebarLabelIfNeeded(workspaceName)
}

@MainActor
private func clearOrphanedSidebarDraftWorkspaceLabels() {
    for workspaceName in config.workspaceSidebar.workspaceLabels.keys
    where isSidebarDraftWorkspaceName(workspaceName) && winMuxWorkspaceState.workspace(named: workspaceName) == nil
    {
        clearSidebarDraftWorkspaceLabelIfNeeded(workspaceName)
    }
}

@MainActor
func workspaceHasSidebarVisibleWindows(_ workspace: Workspace) -> Bool {
    !workspace.rootTilingContainer.isEffectivelyEmpty ||
        !workspace.floatingWindows.isEmpty
}

@MainActor
func workspaceOwnedMinimizedWindows(_ workspace: Workspace) -> [Window] {
    macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self).filter {
        switch $0.layoutReason {
            case .macos(_, let prevWorkspaceName): prevWorkspaceName == workspace.name
            case .standard: false
        }
    }
}

@MainActor
func workspaceHasLifecycleWindows(_ workspace: Workspace) -> Bool {
    !workspace.isEffectivelyEmpty || !workspaceOwnedMinimizedWindows(workspace).isEmpty
}

@MainActor
func isUserFacingWorkspace(_ workspace: Workspace, focusedWorkspace: Workspace? = nil) -> Bool {
    !workspace.isArchived &&
        (
            workspaceHasSidebarVisibleWindows(workspace) ||
                workspace.isVisible ||
                workspace.isConfiguredPersistent ||
                !workspaceOwnedMinimizedWindows(workspace).isEmpty ||
                workspaceIsRetainedEmptySlot(workspace)
        )
}

@MainActor
private func workspaceIsRetainedEmptySlot(_ workspace: Workspace) -> Bool {
    retainedEmptyWorkspaceIdsByScope()[workspace.scope] == workspace.id
}

@MainActor
private func retainedEmptyWorkspaceIdsByScope() -> [WorkspaceScope: WorkspaceId] {
    let scopes = Set(Workspace.all.filter { !$0.isArchived }.map(\.scope))
    return Dictionary(
        uniqueKeysWithValues: scopes.compactMap { scope in
            retainedEmptyWorkspaceId(in: scope).map { (scope, $0) }
        },
    )
}

@MainActor
private func retainedEmptyWorkspaceId(in scope: WorkspaceScope) -> WorkspaceId? {
    let orderedWorkspaces = orderedWorkspaces(in: scope)
    let ordinaryEmptyWorkspaces = orderedWorkspaces.filter(\.isOrdinaryEmptySlot)
    guard !ordinaryEmptyWorkspaces.isEmpty else { return nil }

    let hasAnchors = orderedWorkspaces.contains(where: workspaceAnchorsEmptySlot)
    guard hasAnchors else {
        return ordinaryEmptyWorkspaces.first(where: \.isVisible)?.id ?? ordinaryEmptyWorkspaces.first?.id
    }

    if let visibleEmptyWorkspace = ordinaryEmptyWorkspaces.first(where: \.isVisible),
       workspaceHasAdjacentAnchor(visibleEmptyWorkspace, in: orderedWorkspaces)
    {
        return visibleEmptyWorkspace.id
    }
    return nil
}

@MainActor
private func workspaceAnchorsEmptySlot(_ workspace: Workspace) -> Bool {
    workspaceHasLifecycleWindows(workspace) || workspace.isConfiguredPersistent
}

@MainActor
private func workspaceHasAdjacentAnchor(_ workspace: Workspace, in orderedWorkspaces: [Workspace]) -> Bool {
    guard let index = orderedWorkspaces.firstIndex(of: workspace) else { return false }
    return orderedWorkspaces.getOrNil(atIndex: index - 1).map(workspaceAnchorsEmptySlot) == true ||
        orderedWorkspaces.getOrNil(atIndex: index + 1).map(workspaceAnchorsEmptySlot) == true
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
    let sidebarLabel = config.workspaceSidebar.workspaceLabels[workspaceName]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !sidebarLabel.isEmpty {
        return sidebarLabel
    }
    return workspaceDefaultDisplayName(workspaceName)
}

@MainActor
func userFacingWorkspaces(_ workspaces: [Workspace], focusedWorkspace: Workspace? = nil) -> [Workspace] {
    workspaces.filter { isUserFacingWorkspace($0, focusedWorkspace: focusedWorkspace) }
}

@MainActor
func shouldShowWorkspaceInSidebar(_ workspace: Workspace, currentFocus: LiveFocus, isEditingWorkspace: Bool) -> Bool {
    isEditingWorkspace || isUserFacingWorkspace(workspace, focusedWorkspace: currentFocus.workspace)
}

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

@MainActor
private func automaticWorkspaceDisplayIndex(_ workspace: Workspace, focusedWorkspace: Workspace?) -> Int? {
    orderedUserFacingWorkspaces(in: workspace.scope, focusedWorkspace: focusedWorkspace)
        .filter(\.usesAutomaticDisplayName)
        .firstIndex(of: workspace)
        .map { $0 + 1 }
}

private func automaticWorkspaceDisplayIndexFallback(_ workspaceName: String) -> Int? {
    sidebarDraftWorkspaceIndex(workspaceName) ?? automaticWorkspaceIndex(workspaceName)
}

func parsePositiveWorkspaceDisplayIndex(_ workspaceName: String) -> Int? {
    guard let targetIndex = Int(workspaceName),
          targetIndex > 0,
          String(targetIndex) == workspaceName
    else {
        return nil
    }
    return targetIndex
}

@MainActor
func scopedAutomaticDisplayWorkspaces(current: Workspace) -> [Workspace] {
    orderedUserFacingWorkspaces(in: current.scope, focusedWorkspace: current)
        .filter(\.usesAutomaticDisplayName)
}

@MainActor
func createAdjacentTransientBlankWorkspaceIfAllowed(named workspaceName: String, from current: Workspace) -> Workspace? {
    guard let targetIndex = parsePositiveWorkspaceDisplayIndex(workspaceName) else {
        return nil
    }
    let automaticDisplayWorkspaces = scopedAutomaticDisplayWorkspaces(current: current)
    guard targetIndex == automaticDisplayWorkspaces.count + 1 else { return nil }
    if let lastWorkspace = automaticDisplayWorkspaces.last,
       automaticDisplayWorkspaces.count > 1,
       lastWorkspace.isOrdinaryEmptySlot {
        return nil
    }

    let workspace = Workspace.get(byName: nextSidebarCreatedWorkspaceName(projectId: current.projectId, monitor: current.workspaceMonitor))
    workspace.markAsTransientBlank()
    workspace.assignProject(current.projectId)
    workspace.assignLane(current.laneId)
    return workspace
}

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
private func workspaceProjectDisplayName(_ projectId: WorkspaceProjectId, fallbackName: String) -> String {
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

private func workspaceProjectNameIndex(_ project: WorkspaceProject) -> Int? {
    guard project.name.hasPrefix("Project ") else { return nil }
    return Int(project.name.replacingOccurrences(of: "Project ", with: ""))
}

private func workspaceProjectIdIndex(_ projectId: WorkspaceProjectId) -> Int? {
    guard projectId.rawValue.hasPrefix("project-") else { return nil }
    return Int(projectId.rawValue.replacingOccurrences(of: "project-", with: ""))
}

@MainActor
private func materializePersistedWorkspaceProjects() {
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
func switchWorkspaceProject(_ projectId: WorkspaceProjectId, on monitor: Monitor) -> Workspace? {
    materializePersistedWorkspaceProjects()
    guard winMuxWorkspaceState.projectsById[projectId] != nil else { return nil }
    let laneId = DisplayLaneId(monitor)
    let rememberedWorkspace = winMuxWorkspaceState.projectsById[projectId]?
        .lastActiveWorkspaceByLane[laneId]
        .flatMap { winMuxWorkspaceState.workspaceById[$0] }
    let workspace = rememberedWorkspace
        ?? preferredWorkspace(projectId: projectId, monitor: monitor)
        ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
    return monitor.setActiveWorkspace(workspace) ? workspace : nil
}

@MainActor
private func preferredWorkspace(projectId: WorkspaceProjectId, monitor: Monitor) -> Workspace? {
    workspaceProjectLaneWorkspaces(projectId: projectId, laneId: DisplayLaneId(monitor))
        .filter { !$0.isArchived }
        .first
}

@MainActor
private func createBlankWorkspace(projectId: WorkspaceProjectId, monitor: Monitor) -> Workspace {
    let workspace = Workspace.get(byName: nextAutomaticWorkspaceName(projectId: projectId, monitor: monitor))
    workspace.markAsTransientBlank()
    workspace.assignProject(projectId)
    workspace.assignLane(DisplayLaneId(monitor))
    return workspace
}

@MainActor
func getOrCreateAdjacentBlankWorkspace(projectId: WorkspaceProjectId, monitor: Monitor) -> Workspace {
    let scope = workspaceScope(projectId: projectId, monitor: monitor)
    if let workspaceId = retainedEmptyWorkspaceId(in: scope),
       let workspace = winMuxWorkspaceState.workspaceById[workspaceId]
    {
        return workspace
    }
    return createBlankWorkspace(projectId: projectId, monitor: monitor)
}

@MainActor
private func deleteWorkspace(_ workspace: Workspace) throws {
    let fallback = workspaceFallbackForDeletion(
        excluding: workspace,
        projectId: workspace.projectId,
        monitor: workspace.workspaceMonitor,
    )
    moveWorkspaceContents(from: workspace, to: fallback)
    if workspace.isVisible {
        check(
            workspace.workspaceMonitor.setActiveWorkspace(fallback),
            "Can't activate fallback workspace '\(fallback.name)' while deleting workspace '\(workspace.name)'",
        )
    }
    if focus.workspace == workspace {
        _ = setFocus(to: fallback.toLiveFocus())
    }
    removeWorkspaceFromRegistry(workspace)
    checkWorkspaceHierarchyInvariants()
}

@MainActor
private func workspaceFallbackForDeletion(
    excluding workspace: Workspace,
    projectId: WorkspaceProjectId,
    monitor: Monitor,
) -> Workspace {
    closestWorkspaceForDeletion(
        excluding: workspace,
        projectId: projectId,
        monitor: monitor,
    )
        ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
}

@MainActor
private func closestWorkspaceForDeletion(
    excluding workspace: Workspace,
    projectId: WorkspaceProjectId,
    monitor: Monitor,
) -> Workspace? {
    let scopedCandidates = userFacingWorkspaces(
        orderedWorkspaces(in: workspaceScope(projectId: projectId, monitor: monitor)),
        focusedWorkspace: focus.workspace,
    )
    let automaticCandidates = scopedCandidates.filter(\.usesAutomaticDisplayName)
    let candidates = workspace.usesAutomaticDisplayName && automaticCandidates.contains(workspace)
        ? automaticCandidates
        : scopedCandidates

    guard let deletedIndex = candidates.firstIndex(where: { $0 === workspace }) else {
        return candidates.first { $0 !== workspace }
    }
    if let next = candidates.getOrNil(atIndex: deletedIndex + 1) {
        return next
    }
    if deletedIndex > 0 {
        return candidates[deletedIndex - 1]
    }
    return nil
}

@MainActor
private func moveWorkspaceContents(from source: Workspace, to target: Workspace) {
    guard source != target else { return }
    for child in source.children {
        switch child.nodeCases {
            case .window(let window):
                window.bind(to: target, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            case .tilingContainer(let container):
                container.bind(to: target.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            case .macosFullscreenWindowsContainer(let container):
                for window in container.children.filterIsInstance(of: Window.self) {
                    window.bind(to: target.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                }
            case .macosHiddenAppsWindowsContainer(let container):
                for window in container.children.filterIsInstance(of: Window.self) {
                    window.bind(to: target.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                }
            case .workspace, .macosMinimizedWindowsContainer, .macosPopupWindowsContainer:
                break
        }
    }
    for window in workspaceOwnedMinimizedWindows(source) {
        switch window.layoutReason {
            case .macos(let prevParentKind, _):
                window.layoutReason = .macos(prevParentKind: prevParentKind, prevWorkspaceName: target.name)
            case .standard:
                break
        }
    }
}

@MainActor
private func removeWorkspaceFromRegistry(_ workspace: Workspace) {
    clearWorkspaceSidebarLabelIfNeeded(workspace.name)
    _ = winMuxWorkspaceState.removeWorkspace(workspace)
}

@MainActor
private func pruneEmptyWorkspaces() {
    let retainedEmptyWorkspaceIds = retainedEmptyWorkspaceIdsByScope()
    let focusedWorkspaceBeforePrune = focus.workspace
    let workspacesToRemove = Workspace.all.filter {
        !workspaceShouldSurviveReconciliation($0, retainedEmptyWorkspaceIds: retainedEmptyWorkspaceIds)
    }
    var focusedReplacement: Workspace?

    for workspace in workspacesToRemove {
        let replacement = replacementWorkspaceForPrunedWorkspace(
            workspace,
            retainedEmptyWorkspaceIds: retainedEmptyWorkspaceIds,
        )
        if workspace.isVisible, let replacement {
            check(
                workspace.workspaceMonitor.setActiveWorkspace(replacement),
                "Can't replace pruned empty workspace '\(workspace.name)' with '\(replacement.name)'",
            )
        }
        if workspace == focusedWorkspaceBeforePrune {
            focusedReplacement = focusReplacementForPrunedWorkspace(workspace) ?? replacement
        }
        removeWorkspaceFromRegistry(workspace)
    }

    if let focusedReplacement, focus.workspace != focusedReplacement {
        _ = setFocus(to: focusedReplacement.toLiveFocus())
    }
}

@MainActor
private func focusReplacementForPrunedWorkspace(_ workspace: Workspace) -> Workspace? {
    if !workspace.isVisible,
       let activeWorkspaceId = winMuxWorkspaceState.lanesById[workspace.laneId]?.activeWorkspaceId,
       activeWorkspaceId != workspace.id,
       let activeWorkspace = winMuxWorkspaceState.workspaceById[activeWorkspaceId]
    {
        return activeWorkspace
    }
    return nil
}

@MainActor
private func workspaceShouldSurviveReconciliation(
    _ workspace: Workspace,
    retainedEmptyWorkspaceIds: [WorkspaceScope: WorkspaceId],
) -> Bool {
    guard !workspace.isArchived else { return false }
    return workspaceHasLifecycleWindows(workspace) ||
        workspace.isConfiguredPersistent ||
        retainedEmptyWorkspaceIds[workspace.scope] == workspace.id
}

@MainActor
private func replacementWorkspaceForPrunedWorkspace(
    _ workspace: Workspace,
    retainedEmptyWorkspaceIds: [WorkspaceScope: WorkspaceId],
) -> Workspace? {
    if let retainedWorkspaceId = retainedEmptyWorkspaceIds[workspace.scope],
       retainedWorkspaceId != workspace.id,
       let retainedWorkspace = winMuxWorkspaceState.workspaceById[retainedWorkspaceId]
    {
        return retainedWorkspace
    }
    if let candidate = orderedWorkspaces(in: workspace.scope).first(where: {
        $0.id != workspace.id &&
            workspaceShouldSurviveReconciliation($0, retainedEmptyWorkspaceIds: retainedEmptyWorkspaceIds) &&
            (workspaceHasSidebarVisibleWindows($0) || $0.isConfiguredPersistent)
    }) {
        return candidate
    }
    if workspace.isVisible {
        return createBlankWorkspace(projectId: workspace.projectId, monitor: workspace.workspaceMonitor)
    }
    return nil
}

@MainActor
private func ensureVisibleActiveProjectWorkspaces() {
    for monitor in monitors where winMuxWorkspaceState.visibleWorkspace(for: monitor) == nil {
        let projectId = activeWorkspaceProjectId(for: monitor)
        let workspace = preferredWorkspace(projectId: projectId, monitor: monitor)
            ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
        check(monitor.setActiveWorkspace(workspace))
    }
}

final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let id: WorkspaceId
    private(set) var name: String
    nonisolated private var nameLogicalSegments: StringLogicalSegments
    private(set) var namingStyle: WorkspaceNamingStyle = .explicit
    var projectId: WorkspaceProjectId = workspaceProjectDefaultId
    var laneId: DisplayLaneId
    fileprivate var lifecycle: WorkspaceLifecycle = .durable

    @MainActor
    private init(_ name: String) {
        self.id = winMuxWorkspaceState.nextWorkspaceId()
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        self.laneId = DisplayLaneId(mainMonitor)
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
    }

    @MainActor static var all: [Workspace] {
        winMuxWorkspaceState.workspaceById.values.sorted()
    }

    @MainActor static func get(byName name: String) -> Workspace {
        if let existing = winMuxWorkspaceState.workspace(named: name) {
            return existing
        } else {
            let workspace = Workspace(name)
            winMuxWorkspaceState.registerWorkspace(workspace)
            return workspace
        }
    }

    @MainActor static func existing(byName name: String) -> Workspace? {
        winMuxWorkspaceState.workspace(named: name)
    }

    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.nameLogicalSegments < rhs.nameLogicalSegments
    }

    override func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        workspaceMonitor.visibleRectPaddedByOuterGaps.getDimension(targetOrientation)
    }

    override func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        die("It's not possible to change weight of Workspace")
    }

    @MainActor
    var description: String {
        let description = [
            ("id", id.rawValue),
            ("name", name),
            ("projectId", projectId.rawValue),
            ("laneId", laneId.description),
            ("lifecycle", lifecycle.rawValue),
            ("isVisible", String(isVisible)),
            ("isEffectivelyEmpty", String(isEffectivelyEmpty)),
            ("namingStyle", namingStyle.rawValue),
        ].map { "\($0.0): '\(String(describing: $0.1))'" }.joined(separator: ", ")
        return "Workspace(\(description))"
    }

    @MainActor
    static func reconcileWorkspaceState() {
        for workspace in winMuxWorkspaceState.workspaceById.values {
            workspace.refreshEmptyLifecycle()
        }
        winMuxWorkspaceState.pruneProjectWorkspaceIndexes()
        pruneEmptyWorkspaces()
        clearOrphanedSidebarDraftWorkspaceLabels()
        ensureVisibleActiveProjectWorkspaces()
        checkWorkspaceHierarchyInvariants()
    }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        check((lhs === rhs) == (lhs.id == rhs.id), "lhs: \(lhs) rhs: \(rhs)")
        return lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

}

extension Workspace {
    @MainActor
    func seedMonitorIfNeeded(_ monitor: Monitor) {
        guard !isVisible, forceAssignedMonitor == nil else { return }
        assignLane(DisplayLaneId(monitor))
    }

    @MainActor
    func assignLane(_ laneId: DisplayLaneId) {
        guard self.laneId != laneId else { return }
        winMuxWorkspaceState.moveWorkspace(self, to: laneId)
    }

    @MainActor
    func assignProject(_ projectId: WorkspaceProjectId) {
        guard self.projectId != projectId else { return }
        winMuxWorkspaceState.assignWorkspace(self, to: projectId)
    }

    @MainActor
    func markAsSidebarManaged() {
        markAsAutomaticallyNamed()
        lifecycle = .durable
    }

    @MainActor
    func markAsTransientBlank() {
        markAsAutomaticallyNamed()
        lifecycle = .transient
    }

    @MainActor
    func markAsAutomaticallyNamed() {
        namingStyle = .automatic
    }

    @MainActor
    func restoreNamingStyle(_ namingStyle: WorkspaceNamingStyle) {
        self.namingStyle = namingStyle
    }

    @MainActor
    func refreshEmptyLifecycle() {
        if workspaceHasLifecycleWindows(self), lifecycle == .transient {
            lifecycle = .durable
        }
    }

    @MainActor
    var isConfiguredPersistent: Bool {
        config.persistentWorkspaces.contains(name)
    }

    @MainActor
    var isOrdinaryEmptySlot: Bool {
        !workspaceHasLifecycleWindows(self) && !isConfiguredPersistent
    }

    var usesAutomaticDisplayName: Bool {
        namingStyle == .automatic
    }

    @MainActor
    var isVisible: Bool {
        winMuxWorkspaceState.lanesById.values.contains { $0.activeWorkspaceId == id }
    }
    @MainActor
    var workspaceMonitor: Monitor {
        forceAssignedMonitor ?? laneId.topLeftCorner.monitorApproximation
    }

    @MainActor
    var preferredMonitorPointForTesting: CGPoint? {
        laneId.topLeftCorner
    }

    @MainActor
    var scope: WorkspaceScope {
        WorkspaceScope(projectId: projectId, laneId: laneId)
    }

    var isArchived: Bool {
        lifecycle == .archived
    }
}

extension Monitor {
    @MainActor
    var activeWorkspace: Workspace {
        if let existing = winMuxWorkspaceState.visibleWorkspace(for: self) {
            return existing
        }
        rearrangeWorkspacesOnMonitors()
        return self.activeWorkspace
    }

    @MainActor
    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        rect.topLeftCorner.setActiveWorkspace(workspace)
    }
}

@MainActor
func gcMonitors() {
    rearrangeWorkspacesOnMonitors()
}

extension CGPoint {
    @MainActor
    fileprivate func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        if !isValidAssignment(workspace: workspace, screen: self) {
            return false
        }
        let laneId = DisplayLaneId(topLeftCorner: self)
        _ = winMuxWorkspaceState.setActiveWorkspace(workspace, on: laneId)
        checkWorkspaceHierarchyInvariants()
        return true
    }
}

@MainActor
private func checkWorkspaceHierarchyInvariants() {
    for workspace in Workspace.all {
        check(winMuxWorkspaceState.projectsById[workspace.projectId] != nil, "Workspace '\(workspace.name)' references missing project '\(workspace.projectId)'")
    }

    for (laneId, lane) in winMuxWorkspaceState.lanesById {
        if let activeWorkspaceId = lane.activeWorkspaceId {
            check(winMuxWorkspaceState.workspaceById[activeWorkspaceId] != nil, "Display lane '\(laneId)' references missing workspace '\(activeWorkspaceId)'")
        }
    }
}

@MainActor
private func rearrangeWorkspacesOnMonitors() {
    var oldVisibleMonitors: Set<DisplayLaneId> = winMuxWorkspaceState.lanesById.keys.toSet()

    let newMonitors = monitors.map(DisplayLaneId.init)
    var newMonitorToOldMonitorMapping: [DisplayLaneId: DisplayLaneId] = [:]
    for newMonitor in newMonitors {
        if let oldMonitor = oldVisibleMonitors.minBy({ ($0.topLeftCorner - newMonitor.topLeftCorner).vectorLength }) {
            check(oldVisibleMonitors.remove(oldMonitor) != nil)
            newMonitorToOldMonitorMapping[newMonitor] = oldMonitor
        }
    }

    let oldLanesById = winMuxWorkspaceState.lanesById
    winMuxWorkspaceState.lanesById = [:]

    for newMonitor in newMonitors {
        let newScreen = newMonitor.topLeftCorner
        if let existingVisibleWorkspace = newMonitorToOldMonitorMapping[newMonitor]
            .flatMap({ oldLanesById[$0]?.activeWorkspaceId })
            .flatMap({ winMuxWorkspaceState.workspaceById[$0] }),
           newScreen.setActiveWorkspace(existingVisibleWorkspace)
        {
            continue
        }
        let workspace = getOrCreateLaneFallbackWorkspace(forPoint: newScreen)
        check(newScreen.setActiveWorkspace(workspace),
              "Generated incompatible fallback workspace (\(workspace)) for the display lane (\(newScreen)")
    }
}

@MainActor
private func isValidAssignment(workspace: Workspace, screen: CGPoint) -> Bool {
    if let forceAssigned = workspace.forceAssignedMonitor, forceAssigned.rect.topLeftCorner != screen {
        return false
    } else {
        return true
    }
}
