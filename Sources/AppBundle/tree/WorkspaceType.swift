import AppKit
import Common

final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let id: WorkspaceId
    private(set) var name: String
    nonisolated private var nameLogicalSegments: StringLogicalSegments
    private(set) var namingStyle: WorkspaceNamingStyle = .explicit
    var projectId: WorkspaceProjectId = workspaceProjectDefaultId
    var laneId: DisplayLaneId
    var lifecycle: WorkspaceLifecycle = .durable

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
        repairInvalidVisibleWorkspaceAssignments()
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
        guard !isVisible else { return }
        assignLane(DisplayLaneId(forceAssignedMonitor ?? monitor))
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
