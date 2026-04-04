import AppKit
import Common

@MainActor private var workspaceNameToWorkspace: [String: Workspace] = [:]
private let sidebarDraftWorkspacePrefix = "__sidebar_draft_workspace_"
private let internalStubWorkspacePrefix = "__internal_stub_workspace_"

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

private func lowestUnusedPositiveIndex(_ usedIndices: Set<Int>) -> Int {
    var candidate = 1
    while usedIndices.contains(candidate) {
        candidate += 1
    }
    return candidate
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
private func nextAutomaticWorkspaceName() -> String {
    String(lowestUnusedPositiveIndex(Set(workspaceNameToWorkspace.keys.compactMap(automaticWorkspaceIndex))))
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
func nextSidebarCreatedWorkspaceName() -> String {
    nextAutomaticWorkspaceName()
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
private func clearSidebarDraftWorkspaceLabelIfNeeded(_ workspaceName: String) {
    guard isSidebarDraftWorkspaceName(workspaceName),
          config.workspaceSidebar.workspaceLabels.removeValue(forKey: workspaceName) != nil
    else { return }
    if !isUnitTest {
        try? persistWorkspaceSidebarLabel(workspaceName: workspaceName, label: nil)
    }
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
            workspaceHasSidebarVisibleWindows(workspace) ||
                (workspace.isVisible && !workspace.isEffectivelyEmpty) ||
                workspace.shouldPersistWhenEmpty(focusedWorkspace: focusedWorkspace)
        )
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
    // Workspace naming is derived from current live workspaces. No allocator state to reset.
}

@MainActor
private func automaticWorkspaceDisplayIndex(_ workspace: Workspace, focusedWorkspace: Workspace?) -> Int? {
    userFacingWorkspaces(Workspace.all, focusedWorkspace: focusedWorkspace)
        .filter(\.usesAutomaticDisplayName)
        .firstIndex(of: workspace)
        .map { $0 + 1 }
}

private func automaticWorkspaceDisplayIndexFallback(_ workspaceName: String) -> Int? {
    sidebarDraftWorkspaceIndex(workspaceName) ?? automaticWorkspaceIndex(workspaceName)
}

final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let name: String
    nonisolated private let nameLogicalSegments: StringLogicalSegments
    /// `assignedMonitorPoint` must be interpreted only when the workspace is invisible
    fileprivate var assignedMonitorPoint: CGPoint? = nil
    private var retainsFocusedEmptyWorkspace: Bool = false
    private(set) var isSystemStub: Bool = false
    private(set) var namingStyle: WorkspaceNamingStyle = .explicit

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
                !$0.shouldPersistWhenEmpty(focusedWorkspace: focusedWorkspaceBeforeGc)
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
                (workspace.isSystemStub && workspace.isVisible)
            if !shouldKeep {
                clearSidebarDraftWorkspaceLabelIfNeeded(workspace.name)
            }
            return shouldKeep
        }
        screenPointToPrevVisibleWorkspace = screenPointToPrevVisibleWorkspace.filter { _, workspaceName in
            workspaceNameToWorkspace[workspaceName] != nil
        }
        clearOrphanedSidebarDraftWorkspaceLabels()
    }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        check((lhs === rhs) == (lhs.name == rhs.name), "lhs: \(lhs) rhs: \(rhs)")
        return lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension Workspace {
    @MainActor
    func seedMonitorIfNeeded(_ monitor: Monitor) {
        guard !isVisible, assignedMonitorPoint == nil, forceAssignedMonitor == nil else { return }
        assignedMonitorPoint = monitor.rect.topLeftCorner
    }

    @MainActor
    func markAsSidebarManaged() {
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
}

@MainActor
func materializeWorkspaceForUserWindowIfNeeded(_ workspace: Workspace) -> Workspace {
    guard workspace.isSystemStub else { return workspace }

    let replacement = Workspace.get(byName: nextAutomaticWorkspaceName())
    replacement.markAsAutomaticallyNamed()
    replacement.seedMonitorIfNeeded(workspace.workspaceMonitor)
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
        return true
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
