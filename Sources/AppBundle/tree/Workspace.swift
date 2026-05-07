import AppKit
import Common

@MainActor private var workspaceNameToWorkspace: [String: Workspace] = [:]
private let sidebarDraftWorkspacePrefix = "__sidebar_draft_workspace_"
private let internalStubWorkspacePrefix = "__internal_stub_workspace_"
private let internalAutomaticWorkspacePrefix = "__internal_auto_workspace_"
let workspaceProjectDefaultId = "default"

struct WorkspaceProject: Hashable, Identifiable {
    let id: String
    let name: String
}

struct WorkspaceScope: Hashable {
    let projectId: String
    let monitorPoint: CGPoint
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

@MainActor private var workspaceProjectIdToProject: [String: WorkspaceProject] = [
    workspaceProjectDefaultId: WorkspaceProject(id: workspaceProjectDefaultId, name: "Default"),
]
@MainActor private var activeWorkspaceProjectIdByScreenPoint: [CGPoint: String] = [:]

enum WorkspaceNamingStyle: String, Codable, Sendable {
    case explicit
    case automatic
}

@MainActor private var screenPointToPrevVisibleWorkspace: [CGPoint: String] = [:]
@MainActor private var screenPointToVisibleWorkspace: [CGPoint: Workspace] = [:]
@MainActor private var visibleWorkspaceToScreenPoint: [Workspace: CGPoint] = [:]

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
func workspaceScope(projectId: String, monitor: Monitor) -> WorkspaceScope {
    WorkspaceScope(projectId: projectId, monitorPoint: monitor.rect.topLeftCorner)
}

// The returned workspace must be invisible and it must belong to the requested monitor
@MainActor func getStubWorkspace(for monitor: Monitor) -> Workspace {
    getStubWorkspace(forPoint: monitor.rect.topLeftCorner)
}

@MainActor
private func getStubWorkspace(forPoint point: CGPoint) -> Workspace {
    if let prevName = screenPointToPrevVisibleWorkspace[point],
       let prev = Workspace.existing(byName: prevName),
       canReuseWorkspaceAsEmptyMonitorReplacement(prev, point: point)
    {
        return prev
    }
    if let candidate = Workspace.all.first(where: {
        $0.isSystemStub && canReuseWorkspaceAsEmptyMonitorReplacement($0, point: point)
    })
    {
        return candidate
    }
    let stubWorkspace = Workspace.get(byName: nextInternalStubWorkspaceName())
    stubWorkspace.markAsSystemStub()
    stubWorkspace.assignedMonitorPoint = point
    return stubWorkspace
}

@MainActor
private func canReuseWorkspaceAsEmptyMonitorReplacement(_ workspace: Workspace, point: CGPoint) -> Bool {
    guard !workspace.isVisible,
          workspace.workspaceMonitor.rect.topLeftCorner == point,
          workspace.forceAssignedMonitor == nil
    else {
        return false
    }
    return workspace.isSystemStub || workspaceHasLifecycleWindows(workspace)
}

@MainActor
private func nextInternalAutomaticWorkspaceName() -> String {
    let usedIndices = Set(workspaceNameToWorkspace.keys.compactMap(internalAutomaticWorkspaceIndex))
    var candidate = 1
    while usedIndices.contains(candidate) {
        candidate += 1
    }
    return "\(internalAutomaticWorkspacePrefix)\(candidate)"
}

@MainActor
private func nextAutomaticWorkspaceDisplayIndex(projectId: String, monitor: Monitor) -> Int {
    let usedIndices = userFacingWorkspaces(
        Workspace.all.filter { $0.scope == workspaceScope(projectId: projectId, monitor: monitor) },
        focusedWorkspace: focus.workspace,
    )
        .filter(\.usesAutomaticDisplayName)
        .compactMap { automaticWorkspaceDisplayIndex($0, focusedWorkspace: focus.workspace) }
        .toSet()
    return lowestUnusedPositiveIndex(usedIndices)
}

@MainActor
private func nextAutomaticWorkspaceName(projectId: String = workspaceProjectDefaultId, monitor: Monitor = mainMonitor) -> String {
    let displayIndex = nextAutomaticWorkspaceDisplayIndex(projectId: projectId, monitor: monitor)
    let preferredRawName = String(displayIndex)
    if workspaceNameToWorkspace[preferredRawName] == nil {
        return preferredRawName
    }
    return nextInternalAutomaticWorkspaceName()
}

private func internalStubWorkspaceIndex(_ name: String) -> Int? {
    guard name.hasPrefix(internalStubWorkspacePrefix) else { return nil }
    let suffix = name.replacingOccurrences(of: internalStubWorkspacePrefix, with: "")
    return Int(suffix)
}

@MainActor
private func nextInternalStubWorkspaceName() -> String {
    let usedIndices = Set(workspaceNameToWorkspace.keys.compactMap(internalStubWorkspaceIndex))
    var candidate = 1
    while usedIndices.contains(candidate) {
        candidate += 1
    }
    return "\(internalStubWorkspacePrefix)\(candidate)"
}

@MainActor
func nextSidebarDraftWorkspaceName() -> String {
    clearOrphanedSidebarDraftWorkspaceLabels()
    let nextIndex = lowestUnusedPositiveIndex(Set(workspaceNameToWorkspace.keys.compactMap(sidebarDraftWorkspaceIndex)))
    return "\(sidebarDraftWorkspacePrefix)\(nextIndex)"
}

@MainActor
func nextSidebarCreatedWorkspaceName(projectId: String = workspaceProjectDefaultId, monitor: Monitor = mainMonitor) -> String {
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
    where isSidebarDraftWorkspaceName(workspaceName) && workspaceNameToWorkspace[workspaceName] == nil
    {
        clearSidebarDraftWorkspaceLabelIfNeeded(workspaceName)
    }
}

@MainActor
func workspaceHasSidebarVisibleWindows(_ workspace: Workspace) -> Bool {
    workspace.children.filterIsInstance(of: TilingContainer.self).contains { !$0.isEffectivelyEmpty } ||
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
    !workspace.isSystemStub &&
        (
            workspaceIsBaseUserFacing(workspace, focusedWorkspace: focusedWorkspace) ||
                workspaceIsRequiredActiveProjectWorkspace(workspace, focusedWorkspace: focusedWorkspace)
        )
}

@MainActor
private func workspaceIsBaseUserFacing(_ workspace: Workspace, focusedWorkspace: Workspace?) -> Bool {
    workspaceHasSidebarVisibleWindows(workspace) ||
        (workspace.isVisible && !workspace.isEffectivelyEmpty) ||
        workspace.shouldPersistWhenEmpty(focusedWorkspace: focusedWorkspace)
}

@MainActor
private func workspaceIsRequiredActiveProjectWorkspace(_ workspace: Workspace, focusedWorkspace: Workspace?) -> Bool {
    guard workspace.isVisible,
          !workspace.isSystemStub,
          workspace.projectId != workspaceProjectDefaultId,
          activeWorkspaceProjectId(for: workspace.workspaceMonitor) == workspace.projectId
    else {
        return false
    }
    return !Workspace.all.contains {
        $0 != workspace &&
            $0.scope == workspace.scope &&
            !$0.isSystemStub &&
            workspaceIsBaseUserFacing($0, focusedWorkspace: focusedWorkspace)
    }
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
    workspaceProjectIdToProject = [
        workspaceProjectDefaultId: WorkspaceProject(id: workspaceProjectDefaultId, name: workspaceProjectDisplayName(workspaceProjectDefaultId, fallbackName: "Default")),
    ]
    activeWorkspaceProjectIdByScreenPoint = [:]
}

@MainActor
func resetWorkspaceTopologyForTests() {
    screenPointToPrevVisibleWorkspace = [:]
    screenPointToVisibleWorkspace = [:]
    visibleWorkspaceToScreenPoint = [:]
    for workspace in Workspace.all {
        workspace.assignedMonitorPoint = nil
        workspace.retainsFocusedEmptyWorkspace = false
        workspace.isSystemStub = false
    }
}

@MainActor
private func automaticWorkspaceDisplayIndex(_ workspace: Workspace, focusedWorkspace: Workspace?) -> Int? {
    userFacingWorkspaces(Workspace.all, focusedWorkspace: focusedWorkspace)
        .filter { $0.scope == workspace.scope }
        .filter(\.usesAutomaticDisplayName)
        .firstIndex(of: workspace)
        .map { $0 + 1 }
}

private func automaticWorkspaceDisplayIndexFallback(_ workspaceName: String) -> Int? {
    sidebarDraftWorkspaceIndex(workspaceName) ?? automaticWorkspaceIndex(workspaceName)
}

@MainActor
func workspaceProjects() -> [WorkspaceProject] {
    materializePersistedWorkspaceProjects()
    return workspaceProjectIdToProject.values.map {
        WorkspaceProject(id: $0.id, name: workspaceProjectDisplayName($0.id, fallbackName: $0.name))
    }.sorted {
        if $0.id == workspaceProjectDefaultId { return true }
        if $1.id == workspaceProjectDefaultId { return false }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
}

@MainActor
func workspaceProjectName(_ projectId: String) -> String {
    materializePersistedWorkspaceProjects()
    return workspaceProjectDisplayName(projectId, fallbackName: workspaceProjectIdToProject[projectId]?.name ?? "Project")
}

@MainActor
private func workspaceProjectDisplayName(_ projectId: String, fallbackName: String) -> String {
    let label = config.workspaceSidebar.projectLabels[projectId]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return label.isEmpty ? fallbackName : label
}

@MainActor
func activeWorkspaceProjectId(for monitor: Monitor) -> String {
    materializePersistedWorkspaceProjects()
    return activeWorkspaceProjectIdByScreenPoint[monitor.rect.topLeftCorner] ?? workspaceProjectDefaultId
}

@MainActor
func createWorkspaceProject() -> WorkspaceProject {
    materializePersistedWorkspaceProjects()
    let usedNumbers = (
        workspaceProjectIdToProject.keys.compactMap(workspaceProjectIdIndex) +
            workspaceProjectIdToProject.values.compactMap(workspaceProjectNameIndex)
    ).toSet()
    let index = lowestUnusedPositiveIndex(usedNumbers)
    let project = WorkspaceProject(id: "project-\(index)", name: "Project \(index)")
    workspaceProjectIdToProject[project.id] = project
    config.workspaceSidebar.projectLabels[project.id] = project.name
    if !isUnitTest {
        try? persistWorkspaceSidebarProjectLabel(projectId: project.id, label: project.name)
    }
    return project
}

private func workspaceProjectNameIndex(_ project: WorkspaceProject) -> Int? {
    guard project.name.hasPrefix("Project ") else { return nil }
    return Int(project.name.replacingOccurrences(of: "Project ", with: ""))
}

private func workspaceProjectIdIndex(_ projectId: String) -> Int? {
    guard projectId.hasPrefix("project-") else { return nil }
    return Int(projectId.replacingOccurrences(of: "project-", with: ""))
}

@MainActor
private func materializePersistedWorkspaceProjects() {
    for (projectId, label) in config.workspaceSidebar.projectLabels {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, workspaceProjectIdToProject[projectId] == nil else { continue }
        workspaceProjectIdToProject[projectId] = WorkspaceProject(id: projectId, name: name)
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
func renameWorkspaceProject(_ projectId: String, displayName: String) throws {
    materializePersistedWorkspaceProjects()
    guard let project = workspaceProjectIdToProject[projectId] else {
        throw WorkspaceMutationError.projectNotFound(projectId)
    }
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw WorkspaceMutationError.emptyName }
    let duplicate = workspaceProjects().contains {
        $0.id != projectId && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
    }
    guard !duplicate else { throw WorkspaceMutationError.duplicateProjectName(trimmedName) }

    workspaceProjectIdToProject[projectId] = WorkspaceProject(id: projectId, name: trimmedName)
    let defaultName = project.id == workspaceProjectDefaultId ? "Default" : project.name
    let label = trimmedName == defaultName ? nil : trimmedName
    if let label {
        config.workspaceSidebar.projectLabels[projectId] = label
    } else {
        config.workspaceSidebar.projectLabels.removeValue(forKey: projectId)
    }
    if !isUnitTest {
        try persistWorkspaceSidebarProjectLabel(projectId: projectId, label: label)
    }
}

@MainActor
func canDeleteWorkspaceProject(_ projectId: String) -> Bool {
    materializePersistedWorkspaceProjects()
    return projectId != workspaceProjectDefaultId && workspaceProjectIdToProject[projectId] != nil
}

@MainActor
func deleteWorkspaceForSidebar(workspaceName: String) throws {
    guard let workspace = Workspace.existing(byName: workspaceName) else {
        throw WorkspaceMutationError.workspaceNotFound(workspaceName)
    }
    try deleteWorkspace(workspace)
}

@MainActor
func deleteWorkspaceProject(_ projectId: String) throws {
    materializePersistedWorkspaceProjects()
    guard let project = workspaceProjectIdToProject[projectId] else {
        throw WorkspaceMutationError.projectNotFound(projectId)
    }
    guard canDeleteWorkspaceProject(projectId) else {
        throw WorkspaceMutationError.projectCannotBeDeleted(project.name)
    }

    let fallbackId = workspaceProjects().first { $0.id != projectId }?.id ?? workspaceProjectDefaultId
    let activePoints = activeWorkspaceProjectIdByScreenPoint
        .filter { _, activeProjectId in activeProjectId == projectId }
        .map(\.key)
    for point in activePoints {
        _ = switchWorkspaceProject(fallbackId, on: point.monitorApproximation)
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

    workspaceProjectIdToProject.removeValue(forKey: projectId)
    config.workspaceSidebar.projectLabels.removeValue(forKey: projectId)
    if !isUnitTest {
        try persistWorkspaceSidebarProjectLabel(projectId: projectId, label: nil)
    }
    compactAutomaticWorkspaceNames()
    checkWorkspaceHierarchyInvariants()
}

@MainActor
func switchWorkspaceProject(_ projectId: String, on monitor: Monitor) -> Workspace? {
    materializePersistedWorkspaceProjects()
    guard workspaceProjectIdToProject[projectId] != nil else { return nil }
    ensureWorkspaceProjectIsNotOpenElsewhere(projectId: projectId, targetPoint: monitor.rect.topLeftCorner)
    let workspace = preferredWorkspace(projectId: projectId, monitor: monitor) ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
    return monitor.setActiveWorkspace(workspace) ? workspace : nil
}

@MainActor
private func preferredWorkspace(projectId: String, monitor: Monitor) -> Workspace? {
    userFacingWorkspaces(
        Workspace.all.filter { $0.scope == workspaceScope(projectId: projectId, monitor: monitor) },
        focusedWorkspace: focus.workspace,
    )
        .sorted()
        .first
}

@MainActor
private func createBlankWorkspace(projectId: String, monitor: Monitor) -> Workspace {
    let workspace = Workspace.get(byName: nextAutomaticWorkspaceName(projectId: projectId, monitor: monitor))
    workspace.markAsTransientBlank()
    workspace.assignProject(projectId)
    workspace.seedMonitorIfNeeded(monitor)
    return workspace
}

@MainActor
private func deleteWorkspace(_ workspace: Workspace) throws {
    guard !workspace.isSystemStub else {
        throw WorkspaceMutationError.workspaceCannotBeDeleted(workspace.name)
    }
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
    compactAutomaticWorkspaceNames()
    checkWorkspaceHierarchyInvariants()
}

@MainActor
private func workspaceFallbackForDeletion(
    excluding workspace: Workspace,
    projectId: String,
    monitor: Monitor,
) -> Workspace {
    preferredWorkspace(projectId: projectId, monitor: monitor)?.takeIf { $0 != workspace }
        ?? userFacingWorkspaces(
            Workspace.all.filter {
                $0 != workspace && $0.scope == workspaceScope(projectId: projectId, monitor: monitor)
            },
            focusedWorkspace: focus.workspace,
        ).sorted().first
        ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
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
    screenPointToPrevVisibleWorkspace = screenPointToPrevVisibleWorkspace.filter { _, workspaceName in
        workspaceName != workspace.name
    }
    if let point = visibleWorkspaceToScreenPoint.removeValue(forKey: workspace) {
        screenPointToVisibleWorkspace.removeValue(forKey: point)
    }
    workspaceNameToWorkspace.removeValue(forKey: workspace.name)
}

@MainActor
private func fallbackProjectId(excluding projectId: String) -> String {
    let activeProjectIds = activeWorkspaceProjectIdByScreenPoint.values.toSet()
    if let project = workspaceProjects().first(where: { $0.id != projectId && !activeProjectIds.contains($0.id) }) {
        return project.id
    }
    return createWorkspaceProject().id
}

@MainActor
private func ensureWorkspaceProjectIsNotOpenElsewhere(projectId: String, targetPoint: CGPoint) {
    let occupiedPoints = activeWorkspaceProjectIdByScreenPoint
        .filter { point, activeProjectId in point != targetPoint && activeProjectId == projectId }
        .map(\.key)
    for point in occupiedPoints {
        let fallbackId = fallbackProjectId(excluding: projectId)
        let monitor = point.monitorApproximation
        _ = switchWorkspaceProject(fallbackId, on: monitor)
    }
}

@MainActor
private func ensureVisibleActiveProjectWorkspaces() {
    for (point, workspace) in screenPointToVisibleWorkspace where workspace.isSystemStub {
        let monitor = point.monitorApproximation
        let projectId = activeWorkspaceProjectIdByScreenPoint[point] ?? workspaceProjectDefaultId
        guard projectId != workspaceProjectDefaultId,
              workspaceProjectIdToProject[projectId] != nil
        else { continue }
        let replacement = preferredWorkspace(projectId: projectId, monitor: monitor)
            ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
        check(
            point.setActiveWorkspace(replacement),
            "Can't replace system stub workspace '\(workspace.name)' with active project workspace '\(replacement.name)'",
        )
        if focus.workspace == workspace {
            _ = setFocus(to: replacement.toLiveFocus())
        }
    }
}

final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    private(set) var name: String
    nonisolated private var nameLogicalSegments: StringLogicalSegments
    /// `assignedMonitorPoint` must be interpreted only when the workspace is invisible
    fileprivate var assignedMonitorPoint: CGPoint? = nil
    fileprivate var retainsFocusedEmptyWorkspace: Bool = false
    fileprivate(set) var isSystemStub: Bool = false
    private(set) var namingStyle: WorkspaceNamingStyle = .explicit
    fileprivate(set) var projectId: String = workspaceProjectDefaultId

    @MainActor
    private init(_ name: String) {
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
    }

    @MainActor static var all: [Workspace] {
        workspaceNameToWorkspace.values.sorted()
    }

    @MainActor static func get(byName name: String) -> Workspace {
        if let existing = workspaceNameToWorkspace[name] {
            return existing
        } else {
            let workspace = Workspace(name)
            workspaceNameToWorkspace[name] = workspace
            return workspace
        }
    }

    @MainActor static func existing(byName name: String) -> Workspace? {
        workspaceNameToWorkspace[name]
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
            ("name", name),
            ("projectId", projectId),
            ("isVisible", String(isVisible)),
            ("isEffectivelyEmpty", String(isEffectivelyEmpty)),
            ("retainFocusedEmpty", String(retainsFocusedEmptyWorkspace)),
            ("isSystemStub", String(isSystemStub)),
            ("namingStyle", namingStyle.rawValue),
        ].map { "\($0.0): '\(String(describing: $0.1))'" }.joined(separator: ", ")
        return "Workspace(\(description))"
    }

    @MainActor
    static func garbageCollectUnusedWorkspaces() {
        for workspace in workspaceNameToWorkspace.values {
            workspace.refreshEmptyLifecycle()
        }

        let focusedWorkspaceBeforeGc = focus.workspace
        let visibleEmptyWorkspacesToReplace = workspaceNameToWorkspace.values.filter {
            $0.isVisible &&
                !workspaceHasLifecycleWindows($0) &&
                !$0.isSystemStub &&
                !$0.shouldPersistWhenEmpty(focusedWorkspace: focusedWorkspaceBeforeGc) &&
                !workspaceIsRequiredActiveProjectWorkspace($0, focusedWorkspace: focusedWorkspaceBeforeGc)
        }
        var focusedReplacement: Workspace? = nil
        for workspace in visibleEmptyWorkspacesToReplace {
            let replacement = getStubWorkspace(for: workspace.workspaceMonitor)
            check(
                workspace.workspaceMonitor.setActiveWorkspace(replacement),
                "Can't replace empty workspace '\(workspace.name)' on monitor '\(workspace.workspaceMonitor.name)'",
            )
            if workspace == focusedWorkspaceBeforeGc {
                focusedReplacement = replacement
            }
        }
        if let focusedReplacement, focus.workspace != focusedReplacement {
            _ = setFocus(to: focusedReplacement.toLiveFocus())
        }

        workspaceNameToWorkspace = workspaceNameToWorkspace.filter { (_, workspace: Workspace) in
            let shouldKeep =
                workspaceHasLifecycleWindows(workspace) ||
                workspace.shouldPersistWhenEmpty(focusedWorkspace: focus.workspace) ||
                workspaceIsRequiredActiveProjectWorkspace(workspace, focusedWorkspace: focus.workspace) ||
                (workspace.isSystemStub && workspace.isVisible)
            if !shouldKeep {
                clearWorkspaceSidebarLabelIfNeeded(workspace.name)
            }
            return shouldKeep
        }
        screenPointToPrevVisibleWorkspace = screenPointToPrevVisibleWorkspace.filter { _, workspaceName in
            workspaceNameToWorkspace[workspaceName] != nil
        }
        clearOrphanedSidebarDraftWorkspaceLabels()
        ensureVisibleActiveProjectWorkspaces()
        compactAutomaticWorkspaceNames()
        checkWorkspaceHierarchyInvariants()
    }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        check((lhs === rhs) == (lhs.name == rhs.name), "lhs: \(lhs) rhs: \(rhs)")
        return lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    @MainActor
    fileprivate func rename(to newName: String) {
        let oldName = name
        guard oldName != newName else { return }
        check(workspaceNameToWorkspace[oldName] === self)
        check(workspaceNameToWorkspace[newName] == nil)

        workspaceNameToWorkspace.removeValue(forKey: oldName)
        name = newName
        nameLogicalSegments = newName.toLogicalSegments()
        workspaceNameToWorkspace[newName] = self

        if let sidebarLabel = config.workspaceSidebar.workspaceLabels.removeValue(forKey: oldName) {
            config.workspaceSidebar.workspaceLabels[newName] = sidebarLabel
            if !isUnitTest {
                try? persistWorkspaceSidebarLabel(workspaceName: oldName, label: nil)
                try? persistWorkspaceSidebarLabel(workspaceName: newName, label: sidebarLabel)
            }
        }
        screenPointToPrevVisibleWorkspace = screenPointToPrevVisibleWorkspace.mapValues { $0 == oldName ? newName : $0 }
        replaceWorkspaceNameInFocusState(oldName: oldName, newName: newName)
        replaceWorkspaceNameInLayoutReasons(oldName: oldName, newName: newName)
    }
}

@MainActor
private func compactAutomaticWorkspaceNames() {
    let groupedWorkspaces = Dictionary(grouping: Workspace.all.filter(\.usesAutomaticDisplayName)) { workspace in
        workspace.scope
    }
    for automaticallyNamedWorkspaces in groupedWorkspaces.values {
        var usedIndices = Set(
            workspaceNameToWorkspace.values
                .filter { !$0.usesAutomaticDisplayName }
                .compactMap { automaticWorkspaceIndex($0.name) }
        )
        for workspace in automaticallyNamedWorkspaces.sorted() {
            let targetIndex = lowestUnusedPositiveIndex(usedIndices)
            usedIndices.insert(targetIndex)
            let targetName = String(targetIndex)
            if workspace.name == targetName {
                continue
            }
            if workspaceNameToWorkspace[targetName] == nil {
                workspace.rename(to: targetName)
            }
        }
    }
}

@MainActor
private func replaceWorkspaceNameInLayoutReasons(oldName: String, newName: String) {
    let windows =
        Workspace.all.flatMap(\.allLeafWindowsRecursive) +
        macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self)
    for window in windows {
        switch window.layoutReason {
            case .macos(let prevParentKind, let prevWorkspaceName) where prevWorkspaceName == oldName:
                window.layoutReason = .macos(prevParentKind: prevParentKind, prevWorkspaceName: newName)
            case .macos, .standard:
                break
        }
    }
}

extension Workspace {
    @MainActor
    func seedMonitorIfNeeded(_ monitor: Monitor) {
        guard !isVisible, assignedMonitorPoint == nil, forceAssignedMonitor == nil else { return }
        assignedMonitorPoint = monitor.rect.topLeftCorner
    }

    @MainActor
    func assignProject(_ projectId: String) {
        guard self.projectId != projectId else { return }
        if workspaceProjectIdToProject[projectId] == nil {
            workspaceProjectIdToProject[projectId] = WorkspaceProject(
                id: projectId,
                name: workspaceProjectDisplayName(projectId, fallbackName: "Project"),
            )
        }
        self.projectId = projectId
    }

    @MainActor
    func markAsSidebarManaged() {
        markAsAutomaticallyNamed()
        retainsFocusedEmptyWorkspace = true
    }

    @MainActor
    func markAsTransientBlank() {
        markAsAutomaticallyNamed()
        retainsFocusedEmptyWorkspace = true
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
    func markAsSystemStub() {
        isSystemStub = true
        namingStyle = .explicit
        retainsFocusedEmptyWorkspace = false
    }

    @MainActor
    func refreshEmptyLifecycle() {
        guard workspaceHasLifecycleWindows(self) else { return }
        retainsFocusedEmptyWorkspace = false
        isSystemStub = false
    }

    @MainActor
    func shouldRetainEmptyWorkspace(focusedWorkspace: Workspace?) -> Bool {
        focusedWorkspace == self && retainsFocusedEmptyWorkspace
    }

    @MainActor
    var isConfiguredPersistent: Bool {
        config.persistentWorkspaces.contains(name)
    }

    @MainActor
    func shouldPersistWhenEmpty(focusedWorkspace: Workspace?) -> Bool {
        isConfiguredPersistent || shouldRetainEmptyWorkspace(focusedWorkspace: focusedWorkspace)
    }

    var usesAutomaticDisplayName: Bool {
        namingStyle == .automatic && !isSystemStub
    }

    @MainActor
    var isVisible: Bool { visibleWorkspaceToScreenPoint.keys.contains(self) }
    @MainActor
    var workspaceMonitor: Monitor {
        forceAssignedMonitor
            ?? visibleWorkspaceToScreenPoint[self]?.monitorApproximation
            ?? assignedMonitorPoint?.monitorApproximation
            ?? mainMonitor
    }

    @MainActor
    var preferredMonitorPointForTesting: CGPoint? {
        assignedMonitorPoint
    }

    @MainActor
    var scope: WorkspaceScope {
        workspaceScope(projectId: projectId, monitor: workspaceMonitor)
    }
}

@MainActor
func materializeWorkspaceForUserWindowIfNeeded(_ workspace: Workspace) -> Workspace {
    guard workspace.isSystemStub else { return workspace }

    let monitor = workspace.workspaceMonitor
    let replacement = Workspace.get(byName: nextAutomaticWorkspaceName(
        projectId: activeWorkspaceProjectId(for: monitor),
        monitor: monitor,
    ))
    replacement.markAsAutomaticallyNamed()
    replacement.assignProject(activeWorkspaceProjectId(for: monitor))
    replacement.seedMonitorIfNeeded(monitor)
    if workspace.isVisible {
        check(
            workspace.workspaceMonitor.setActiveWorkspace(replacement),
            "Can't materialize replacement workspace for internal stub '\(workspace.name)'",
        )
        if focus.workspace == workspace {
            _ = setFocus(to: replacement.toLiveFocus())
        }
    }
    return replacement
}

extension Monitor {
    @MainActor
    var activeWorkspace: Workspace {
        if let existing = screenPointToVisibleWorkspace[rect.topLeftCorner] {
            return existing
        }
        // What if monitor configuration changed? (frame.origin is changed)
        rearrangeWorkspacesOnMonitors()
        // Normally, recursion should happen only once more because we must take the value from the cache
        // (Unless, monitor configuration data race happens)
        return self.activeWorkspace
    }

    @MainActor
    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        rect.topLeftCorner.setActiveWorkspace(workspace)
    }
}

@MainActor
func gcMonitors() {
    if screenPointToVisibleWorkspace.count != monitors.count {
        rearrangeWorkspacesOnMonitors()
    }
}

extension CGPoint {
    @MainActor
    fileprivate func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        if !isValidAssignment(workspace: workspace, screen: self) {
            return false
        }
        if !workspace.isSystemStub {
            ensureWorkspaceProjectIsNotOpenElsewhere(projectId: workspace.projectId, targetPoint: self)
        }
        if let prevMonitorPoint = visibleWorkspaceToScreenPoint[workspace] {
            visibleWorkspaceToScreenPoint.removeValue(forKey: workspace)
            screenPointToPrevVisibleWorkspace[prevMonitorPoint] =
                screenPointToVisibleWorkspace.removeValue(forKey: prevMonitorPoint)?.name
        }
        if let prevWorkspace = screenPointToVisibleWorkspace[self] {
            screenPointToPrevVisibleWorkspace[self] =
                screenPointToVisibleWorkspace.removeValue(forKey: self)?.name
            visibleWorkspaceToScreenPoint.removeValue(forKey: prevWorkspace)
        }
        visibleWorkspaceToScreenPoint[workspace] = self
        screenPointToVisibleWorkspace[self] = workspace
        workspace.assignedMonitorPoint = self
        if !workspace.isSystemStub {
            activeWorkspaceProjectIdByScreenPoint[self] = workspace.projectId
        }
        checkWorkspaceHierarchyInvariants()
        return true
    }
}

@MainActor
private func checkWorkspaceHierarchyInvariants() {
    for workspace in Workspace.all {
        check(workspaceProjectIdToProject[workspace.projectId] != nil, "Workspace '\(workspace.name)' references missing project '\(workspace.projectId)'")
    }

    var openProjectIds: Set<String> = []
    for (point, workspace) in screenPointToVisibleWorkspace where !workspace.isSystemStub {
        let activeProjectId = activeWorkspaceProjectIdByScreenPoint[point]
        check(
            activeProjectId == workspace.projectId,
            "Visible workspace '\(workspace.name)' project '\(workspace.projectId)' disagrees with active project '\(activeProjectId ?? "nil")'",
        )
        check(
            openProjectIds.insert(workspace.projectId).inserted,
            "Project '\(workspace.projectId)' is open on more than one display",
        )
    }
}

@MainActor
private func rearrangeWorkspacesOnMonitors() {
    var oldVisibleScreens: Set<CGPoint> = screenPointToVisibleWorkspace.keys.toSet()

    let newScreens = monitors.map(\.rect.topLeftCorner)
    var newScreenToOldScreenMapping: [CGPoint: CGPoint] = [:]
    for newScreen in newScreens {
        if let oldScreen = oldVisibleScreens.minBy({ ($0 - newScreen).vectorLength }) {
            check(oldVisibleScreens.remove(oldScreen) != nil)
            newScreenToOldScreenMapping[newScreen] = oldScreen
        }
    }

    let oldScreenPointToVisibleWorkspace = screenPointToVisibleWorkspace
    screenPointToVisibleWorkspace = [:]
    visibleWorkspaceToScreenPoint = [:]

    for newScreen in newScreens {
        if let existingVisibleWorkspace = newScreenToOldScreenMapping[newScreen].flatMap({ oldScreenPointToVisibleWorkspace[$0] }),
           newScreen.setActiveWorkspace(existingVisibleWorkspace)
        {
            continue
        }
        let stubWorkspace = getStubWorkspace(forPoint: newScreen)
        check(newScreen.setActiveWorkspace(stubWorkspace),
              "getStubWorkspace generated incompatible stub workspace (\(stubWorkspace)) for the monitor (\(newScreen)")
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
