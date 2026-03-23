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
    @Published var workspaceSidebarDropPreview: WorkspaceSidebarDropPreviewViewModel? = nil
    @Published var windowTabStrips: [WindowTabStripViewModel] = []
    @Published var isWorkspaceSidebarExpanded: Bool = false
    @Published var workspaceSidebarVisibleWidth: CGFloat = 0
    @Published var workspaceSidebarTopPadding: CGFloat = 12
    @Published var workspaceSidebarHoveredWorkspaceName: String? = nil
    @Published var workspaceSidebarEditingWorkspaceName: String? = nil
    @Published var workspaceSidebarEditingText: String = ""
    @Published var experimentalUISettings: ExperimentalUISettings = ExperimentalUISettings()
    @Published var sponsorshipMessage: String = sponsorshipPrompts.randomElement().orDie()
}

@MainActor func updateTrayText() {
    let sortedMonitors = sortedMonitors
    let focus = focus
    TrayMenuModel.shared.trayText = (activeMode?.takeIf { $0 != mainModeId }?.first.map { "(\($0.uppercased())) " } ?? "") +
        sortedMonitors
        .map {
            let hasFullscreenWindows = $0.activeWorkspace.allLeafWindowsRecursive.contains { $0.isFullscreen }
            let activeWorkspaceName = workspaceDisplayName($0.activeWorkspace.name)
            let formattedActiveWorkspaceName = hasFullscreenWindows ? "[\(activeWorkspaceName)]" : activeWorkspaceName
            return ($0.activeWorkspace == focus.workspace && sortedMonitors.count > 1 ? "*" : "") + formattedActiveWorkspaceName
        }
        .joined(separator: " │ ")
    TrayMenuModel.shared.workspaces = userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).map {
        let apps = $0.allLeafWindowsRecursive.map { $0.app.name?.takeIf { !$0.isEmpty } }.filterNotNil().toSet()
        let dash = " - "
        let suffix = switch true {
            case !apps.isEmpty: dash + apps.sorted().joinTruncating(separator: ", ", length: 25)
            case $0.isVisible: dash + $0.workspaceMonitor.name
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
    var items = sortedMonitors.map {
        let hasFullscreenWindows = $0.activeWorkspace.allLeafWindowsRecursive.contains { $0.isFullscreen }
        return TrayItem(
            type: .workspace,
            name: $0.activeWorkspace.name,
            isActive: $0.activeWorkspace == focus.workspace,
            hasFullscreenWindows: hasFullscreenWindows,
        )
    }
    let mode = activeMode?.takeIf { $0 != mainModeId }?.first.map {
        TrayItem(type: .mode, name: $0.uppercased(), isActive: true, hasFullscreenWindows: false)
    }
    if let mode {
        items.insert(mode, at: 0)
    }
    TrayMenuModel.shared.trayItems = items
}

struct WorkspaceViewModel: Hashable {
    let name: String
    let displayName: String
    let suffix: String
    let isFocused: Bool
    let isEffectivelyEmpty: Bool
    let isVisible: Bool
    let hasFullscreenWindows: Bool
}

struct WorkspaceSidebarWorkspaceViewModel: Hashable, Identifiable {
    let name: String
    let displayName: String
    let sidebarLabel: String
    let isGeneratedName: Bool
    let monitorName: String?
    let isFocused: Bool
    let isVisible: Bool
    let items: [WorkspaceSidebarItemViewModel]

    var id: String { name }
}

struct WorkspaceSidebarItemViewModel: Hashable, Identifiable {
    let kind: WorkspaceSidebarItemKind

    var id: String {
        switch kind {
            case .window(let window):
                "window:\(window.windowId)"
            case .tabGroup(let group):
                group.id
        }
    }
}

enum WorkspaceSidebarItemKind: Hashable {
    case window(WorkspaceSidebarWindowViewModel)
    case tabGroup(WorkspaceSidebarTabGroupViewModel)
}

struct WorkspaceSidebarTabGroupViewModel: Hashable, Identifiable {
    let representativeWindowId: UInt32
    let workspaceName: String
    let title: String
    let windowCount: Int
    let isFocused: Bool
    let tabs: [WorkspaceSidebarWindowViewModel]

    var id: String { "group:\(representativeWindowId)" }
}

struct WorkspaceSidebarWindowViewModel: Hashable, Identifiable {
    let windowId: UInt32
    let workspaceName: String
    let appName: String
    let title: String?
    let isFocused: Bool

    var id: UInt32 { windowId }
}

struct WorkspaceSidebarDropPreviewViewModel: Hashable {
    let sourceWindowId: UInt32
    let label: String
    let targetWorkspaceName: String?
    let targetsNewWorkspace: Bool
    let isTabGroup: Bool
    let windowCount: Int
}

struct WindowTabStripViewModel: Identifiable, Equatable {
    let id: ObjectIdentifier
    let workspaceName: String
    let frame: CGRect
    let tabs: [WindowTabItemViewModel]
}

struct WindowTabItemViewModel: Hashable, Identifiable {
    let windowId: UInt32
    let workspaceName: String
    let title: String
    let isActive: Bool

    var id: UInt32 { windowId }
}

enum TrayItemType: String, Hashable {
    case mode
    case workspace
}

private let validLetters = "A" ... "Z"

struct TrayItem: Hashable, Identifiable {
    let type: TrayItemType
    let name: String
    let isActive: Bool
    let hasFullscreenWindows: Bool
    var systemImageName: String? {
        // System image type is only valid for numbers 0 to 50 and single capital char workspace name
        if let number = Int(name) {
            if !(0 ... 50).contains(number) { return nil }
        } else if name.count == 1 {
            if !validLetters.contains(name) { return nil }
        } else {
            return nil
        }
        let lowercasedName = name.lowercased()
        switch type {
            case .mode:
                return "\(lowercasedName).circle"
            case .workspace:
                if isActive {
                    return "\(lowercasedName).square.fill"
                } else {
                    return "\(lowercasedName).square"
                }
        }
    }
    var id: String {
        return type.rawValue + name
    }
}
