import AppKit
import Common

let sidebarDraftWorkspacePrefix = "__sidebar_draft_workspace_"
let internalAutomaticWorkspacePrefix = "__internal_auto_workspace_"
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
    case projectCloseBlocked(String, Int)
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
            case .projectCloseBlocked(let name, let count):
                "Project '\(name)' was not deleted because \(count) window\(count == 1 ? "" : "s") stayed open."
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

func automaticWorkspaceIndex(_ name: String) -> Int? {
    Int(name)
}

func internalAutomaticWorkspaceIndex(_ name: String) -> Int? {
    guard name.hasPrefix(internalAutomaticWorkspacePrefix) else { return nil }
    let suffix = name.replacingOccurrences(of: internalAutomaticWorkspacePrefix, with: "")
    return Int(suffix)
}

func lowestUnusedPositiveIndex(_ usedIndices: Set<Int>) -> Int {
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
    )
}

@MainActor
func getOrCreateLaneFallbackWorkspace(forPoint point: CGPoint) -> Workspace {
    let monitor = point.monitorApproximation
    return getOrCreateFallbackWorkspace(
        projectId: activeWorkspaceProjectId(for: monitor),
        laneId: DisplayLaneId(topLeftCorner: point),
        monitor: monitor,
    )
}

@MainActor
func getOrCreateFallbackWorkspace(
    projectId: WorkspaceProjectId,
    laneId: DisplayLaneId,
    monitor: Monitor,
) -> Workspace {
    let scope = WorkspaceScope(projectId: projectId, laneId: laneId)
    if let workspaceId = retainedEmptyWorkspaceId(in: scope),
       let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
       isValidAssignment(workspace: workspace, screen: monitor.rect.topLeftCorner)
    {
        return workspace
    }
    if let workspace = workspaceProjectLaneWorkspaces(projectId: projectId, laneId: laneId)
        .first(where: { $0.isEffectivelyEmpty && !$0.isArchived && isValidAssignment(workspace: $0, screen: monitor.rect.topLeftCorner) })
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
    result.append(contentsOf: Workspace.all.filter { !$0.isArchived && seen.insert($0.id).inserted })
    return result
}

@MainActor
func orderedUserFacingWorkspaces(in scope: WorkspaceScope, focusedWorkspace: Workspace? = nil) -> [Workspace] {
    userFacingWorkspaces(orderedWorkspaces(in: scope), focusedWorkspace: focusedWorkspace)
}

@MainActor
func nextInternalAutomaticWorkspaceName() -> String {
    let usedIndices = Set(winMuxWorkspaceState.workspaceIdByName.keys.compactMap(internalAutomaticWorkspaceIndex))
    var candidate = 1
    while usedIndices.contains(candidate) {
        candidate += 1
    }
    return "\(internalAutomaticWorkspacePrefix)\(candidate)"
}

@MainActor
func nextAutomaticWorkspaceDisplayIndex(projectId: WorkspaceProjectId, monitor: Monitor) -> Int {
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
func nextAutomaticWorkspaceName(projectId _: WorkspaceProjectId = workspaceProjectDefaultId, monitor: Monitor = mainMonitor) -> String {
    var candidate = 1
    while true {
        let name = String(candidate)
        if winMuxWorkspaceState.workspaceIdByName[name] == nil,
           isValidAssignment(workspaceName: name, screen: monitor.rect.topLeftCorner)
        {
            return name
        }
        candidate += 1
    }
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
func clearWorkspaceSidebarLabelIfNeeded(_ workspaceName: String) {
    guard config.workspaceSidebar.workspaceLabels.removeValue(forKey: workspaceName) != nil else { return }
    if !isUnitTest {
        try? persistWorkspaceSidebarLabel(workspaceName: workspaceName, label: nil)
    }
}

@MainActor
func clearSidebarDraftWorkspaceLabelIfNeeded(_ workspaceName: String) {
    guard isSidebarDraftWorkspaceName(workspaceName) else { return }
    clearWorkspaceSidebarLabelIfNeeded(workspaceName)
}

@MainActor
func clearOrphanedSidebarDraftWorkspaceLabels() {
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
func workspaceIsRetainedEmptySlot(_ workspace: Workspace) -> Bool {
    retainedEmptyWorkspaceIdsByScope()[workspace.scope] == workspace.id
}

@MainActor
func retainedEmptyWorkspaceIdsByScope() -> [WorkspaceScope: WorkspaceId] {
    let scopes = Set(Workspace.all.filter { !$0.isArchived }.map(\.scope))
    return Dictionary(
        uniqueKeysWithValues: scopes.compactMap { scope in
            retainedEmptyWorkspaceId(in: scope).map { (scope, $0) }
        },
    )
}

@MainActor
func retainedEmptyWorkspaceId(in scope: WorkspaceScope) -> WorkspaceId? {
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
func workspaceAnchorsEmptySlot(_ workspace: Workspace) -> Bool {
    workspaceHasLifecycleWindows(workspace) || workspace.isConfiguredPersistent
}

@MainActor
func workspaceHasAdjacentAnchor(_ workspace: Workspace, in orderedWorkspaces: [Workspace]) -> Bool {
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
func automaticWorkspaceDisplayIndex(_ workspace: Workspace, focusedWorkspace: Workspace?) -> Int? {
    orderedUserFacingWorkspaces(in: workspace.scope, focusedWorkspace: focusedWorkspace)
        .filter(\.usesAutomaticDisplayName)
        .firstIndex(of: workspace)
        .map { $0 + 1 }
}

func automaticWorkspaceDisplayIndexFallback(_ workspaceName: String) -> Int? {
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
