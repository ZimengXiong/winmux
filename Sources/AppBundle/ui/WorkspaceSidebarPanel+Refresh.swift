import AppKit

extension WorkspaceSidebarPanel {
    func refresh() {
        guard let layout = currentSidebarPanelLayout() else {
            stopHoverMonitoring()
            resetHiddenSidebarState()
            return
        }

        if frame != layout.frame {
            workspaceSidebarDropTargets = []
            setFrame(layout.frame, display: true, animate: false)
        }
        if TrayMenuModel.shared.workspaceSidebarVisibleWidth == 0 {
            TrayMenuModel.shared.workspaceSidebarVisibleWidth = TrayMenuModel.shared.isWorkspaceSidebarExpanded
                ? layout.expandedWidth
                : layout.collapsedWidth
        }
        updateMousePassthrough()
        startHoverMonitoring()
        orderFrontRegardless()
    }

    func refreshForCurrentDragIfNeeded() {
        guard isMouseWindowDragInProgress() else { return }
        let targetMonitor = mouseLocation.monitorApproximation
        let screen = NSScreen.screens.getOrNil(atIndex: targetMonitor.monitorAppKitNsScreenScreensId - 1) ?? NSScreen.screens.first
        guard let screen, frame.minX != screen.frame.minX || frame.minY != screen.frame.minY else { return }
        refresh()
    }

    func resetHiddenSidebarState() {
        workspaceSidebarDropTargets = []
        TrayMenuModel.shared.workspaceSidebarDropPreview = nil
        TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = nil
        TrayMenuModel.shared.workspaceSidebarVisibleWidth = 0
        orderOut(nil)
    }
}
