import CoreGraphics

struct WorkspaceSidebarSnapshot: Equatable {
    var workspaces: [WorkspaceSidebarWorkspaceViewModel]
    var projects: [WorkspaceSidebarProjectViewModel]
    var selectedProjectId: WorkspaceProjectId
    var monitorScopes: [WorkspaceSidebarMonitorScopeViewModel]
    var selectedMonitorScopeId: String
    var focusedMonitorScopeId: String
    var showsMonitorSelector: Bool
    var visibleWidth: CGFloat
    var topPadding: CGFloat
    var hoveredWorkspaceName: String?
    var dropPreview: WorkspaceSidebarDropPreviewViewModel?

    static let empty = WorkspaceSidebarSnapshot(
        workspaces: [],
        projects: [],
        selectedProjectId: workspaceProjectDefaultId,
        monitorScopes: [],
        selectedMonitorScopeId: workspaceSidebarDefaultScopeId,
        focusedMonitorScopeId: "",
        showsMonitorSelector: false,
        visibleWidth: 0,
        topPadding: 12,
        hoveredWorkspaceName: nil,
        dropPreview: nil,
    )
}

enum WorkspaceSidebarAction: Equatable {
    case selectWorkspace(String)
    case selectWindow(UInt32, fallbackWorkspace: String)
    case selectProject(WorkspaceProjectId)
    case createProject
    case renameProject(WorkspaceProjectId, displayName: String)
    case setProjectColor(WorkspaceProjectId, colorHex: String?)
    case deleteProject(WorkspaceProjectId)
    case selectMonitorScope(String)
    case createWorkspace(projectId: WorkspaceProjectId, monitorScopeId: String)
    case renameWorkspace(String, displayName: String)
    case resetWorkspace(String)
    case deleteWorkspace(String)
    case hoverWorkspace(String, isHovering: Bool)
    case moveWindow(UInt32, toWorkspace: String)
    case moveTabGroup(UInt32, toWorkspace: String)
    case moveWindowToNewWorkspace(UInt32, projectId: WorkspaceProjectId, monitorScopeId: String)
    case moveTabGroupToNewWorkspace(UInt32, projectId: WorkspaceProjectId, monitorScopeId: String)
    case previewWindowDrop(UInt32, target: WorkspaceSidebarDropTargetKind)
    case previewTabGroupDrop(UInt32, target: WorkspaceSidebarDropTargetKind)
    case clearDropPreview
    case updateWindowDrag(UInt32, subject: WindowDragSubject)
    case finishWindowDrag
    case setDropTargets([WorkspaceSidebarDropTargetFrame])
}

struct WorkspaceSidebarActions {
    var send: @MainActor (WorkspaceSidebarAction) -> Void
    var windowDragChanged: @MainActor (UInt32) -> Void
    var windowDragEnded: @MainActor (UInt32) -> Void
    var tabGroupDragChanged: @MainActor (UInt32) -> Void
    var tabGroupDragEnded: @MainActor (UInt32) -> Void

    init(send: @escaping @MainActor (WorkspaceSidebarAction) -> Void = { _ in }) {
        self.send = send
        windowDragChanged = { send(.updateWindowDrag($0, subject: .window)) }
        windowDragEnded = { _ in send(.finishWindowDrag) }
        tabGroupDragChanged = { send(.updateWindowDrag($0, subject: .group)) }
        tabGroupDragEnded = { _ in send(.finishWindowDrag) }
    }
}
