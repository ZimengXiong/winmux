enum WindowDragIntentKind: Equatable {
    case tabStack(targetWindowId: UInt32)
    case detachTab(windowId: UInt32)
    case stackSplit(targetWindowId: UInt32, position: WindowStackSplitPosition)
    case swap(targetWindowId: UInt32)
    case moveToWorkspace(workspaceName: String)
    case moveToWorkspaceZone(workspaceName: String, zone: WindowDropZone)
    case createWorkspace
    case sidebarHover
}

@MainActor
func isWindowDragIntentKindEnabled(_ kind: WindowDragIntentKind) -> Bool {
    switch kind {
        case .tabStack:
            return config.windowTabs.enabled
        case .detachTab, .stackSplit, .swap, .moveToWorkspace, .moveToWorkspaceZone, .createWorkspace, .sidebarHover:
            return true
    }
}
