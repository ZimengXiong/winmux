import AppKit
import Common

public final class TrayMenuModel: ObservableObject {
    @MainActor public static let shared = TrayMenuModel()

    private init() {}

    @Published var trayText: String = ""
    @Published var trayItems: [TrayItem] = []
    /// Is "layouting" enabled
    @Published var isEnabled: Bool = true
    @Published var workspaces: [WorkspaceViewModel] = []
    @Published var workspaceSidebarWorkspaces: [WorkspaceSidebarWorkspaceViewModel] = []
    @Published var workspaceSidebarProjects: [WorkspaceSidebarProjectViewModel] = []
    @Published var workspaceSidebarSelectedProjectId: WorkspaceProjectId = workspaceProjectDefaultId
    @Published var workspaceSidebarMonitorScopes: [WorkspaceSidebarMonitorScopeViewModel] = []
    @Published var workspaceSidebarSelectedMonitorScopeId: String = workspaceSidebarDefaultScopeId
    @Published var workspaceSidebarFocusedMonitorScopeId: String = ""
    @Published var workspaceSidebarShowsMonitorSelector: Bool = false
    @Published var workspaceSidebarDropPreview: WorkspaceSidebarDropPreviewViewModel? = nil
    @Published var windowTabStrips: [WindowTabStripViewModel] = []
    @Published var isWorkspaceSidebarExpanded: Bool = false
    @Published var workspaceSidebarVisibleWidth: CGFloat = 0
    @Published var workspaceSidebarTopPadding: CGFloat = 12
    @Published var workspaceSidebarHoveredWorkspaceName: String? = nil
    @Published var experimentalUISettings: ExperimentalUISettings = ExperimentalUISettings()

    var visibleWorkspaceSidebarWorkspaces: [WorkspaceSidebarWorkspaceViewModel] {
        workspaceSidebarWorkspaces.filter {
            $0.projectId == workspaceSidebarSelectedProjectId &&
            workspaceSidebarWorkspaceMatchesScope(
                $0,
                selectedScopeId: workspaceSidebarSelectedMonitorScopeId,
                focusedMonitorScopeId: workspaceSidebarFocusedMonitorScopeId,
            )
        }
    }
}

@MainActor func updateTrayText() {
    let focus = focus
    TrayMenuModel.shared.trayText = activeMode?.takeIf { $0 != mainModeId }?.first.map { "(\($0.uppercased()))" } ?? "A"
    TrayMenuModel.shared.workspaces = userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).filter {
        $0.projectId == activeWorkspaceProjectId(for: $0.workspaceMonitor)
    }.map {
        let apps = $0.allLeafWindowsRecursive.map { $0.app.name?.takeIf { !$0.isEmpty } }.filterNotNil().toSet()
        let dash = " - "
        let suffix = switch true {
            case !apps.isEmpty: dash + apps.sorted().joinTruncating(separator: ", ", length: 25)
            default: ""
        }
        let hasFullscreenWindows = $0.allLeafWindowsRecursive.contains { $0.isFullscreen }
        return WorkspaceViewModel(
            name: $0.name,
            displayName: workspaceDisplayName($0.name),
            suffix: suffix,
            isFocused: focus.workspace == $0,
            isEffectivelyEmpty: !workspaceHasSidebarVisibleWindows($0),
            isVisible: $0.isVisible,
            hasFullscreenWindows: hasFullscreenWindows,
        )
    }
    let items = activeMode?.takeIf { $0 != mainModeId }?.first.map {
        TrayItem(type: .mode, name: $0.uppercased(), isActive: true, hasFullscreenWindows: false)
    }.map { [$0] } ?? []
    TrayMenuModel.shared.trayItems = items
}
