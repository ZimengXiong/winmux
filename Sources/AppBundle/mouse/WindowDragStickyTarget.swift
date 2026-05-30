@MainActor
func stickyTargetWindow(for sticky: PendingWindowDragIntent) -> Window? {
    switch sticky.kind {
        case .tabStack(let targetWindowId), .stackSplit(let targetWindowId, _), .swap(let targetWindowId):
            Window.get(byId: targetWindowId)
        case .reorderTab, .detachTab, .moveToWorkspace, .moveToWorkspaceZone, .createWorkspace, .sidebarHover:
            nil
    }
}

@MainActor
func stickyTargetTrackingRect(targetWindow: Window, previewStyle: WindowTabDropPreviewStyle) -> Rect? {
    switch previewStyle {
        case .tabInsert:
            targetWindow.windowDragVisibleRect?.expanded(
                left: windowTabInsertStickyTrackingHorizontalInset,
                right: windowTabInsertStickyTrackingHorizontalInset,
                top: windowTabInsertStickyTrackingTopInset,
                bottom: windowTabInsertStickyTrackingBottomInset
            )
        case .stackSplit, .swap:
            targetWindow.moveNode.windowDragVisibleRect?.expanded(by: 16)
        case .detach, .workspaceMove, .sidebarWorkspaceMove:
            nil
    }
}
