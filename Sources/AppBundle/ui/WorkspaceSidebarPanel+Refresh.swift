import AppKit

extension WorkspaceSidebarPanel {
    func refresh() {
        refresh(on: workspaceSidebarResolvedPanelMonitor())
    }

    func refresh(on monitor: Monitor) {
        guard let layout = currentSidebarPanelLayout(on: monitor) else {
            stopHoverMonitoring()
            resetHiddenSidebarState()
            return
        }

        if frame != layout.frame {
            setFrame(layout.frame, display: true, animate: false)
        }
        if viewModel.workspaceSidebarVisibleWidth == 0 {
            viewModel.workspaceSidebarVisibleWidth = viewModel.isWorkspaceSidebarExpanded
                ? layout.expandedWidth
                : layout.collapsedWidth
        }
        updateMousePassthrough()
        startHoverMonitoring()
        orderFrontRegardless()
    }

    func refreshForCurrentDragIfNeeded() {
        guard isMouseWindowDragInProgress() else { return }
        WorkspaceSidebarPanel.refreshAll()
    }

    func resetHiddenSidebarState() {
        workspaceSidebarDropTargets = []
        TrayMenuModel.shared.workspaceSidebarDropPreview = nil
        TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = nil
        viewModel.workspaceSidebarVisibleWidth = 0
        orderOut(nil)
    }
}
