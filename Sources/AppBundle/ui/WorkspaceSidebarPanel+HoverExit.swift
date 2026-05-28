import SwiftUI

extension WorkspaceSidebarPanel {
    func handleHoverExit(collapsedWidth: CGFloat) {
        debugWorkspaceSidebarHoverLog("handleHoverExit panel=\(monitorScopeId) visible=\(viewModel.workspaceSidebarVisibleWidth) collapsed=\(collapsedWidth) expanded=\(viewModel.isWorkspaceSidebarExpanded) suppressActive=\(Date() < splitBrowseCollapseSuppressedUntil) mouse=\(NSEvent.mouseLocation)")
        pendingExpand?.cancel()
        pendingExpand = nil
        guard Date() >= splitBrowseCollapseSuppressedUntil else {
            debugWorkspaceSidebarHoverLog("handleHoverExit suppressed panel=\(monitorScopeId)")
            return
        }
        guard !shouldLockExpansionForSidebarDrag() else {
            debugWorkspaceSidebarHoverLog("handleHoverExit locked panel=\(monitorScopeId)")
            return
        }
        let needsCollapse =
            viewModel.isWorkspaceSidebarExpanded ||
            viewModel.workspaceSidebarVisibleWidth != collapsedWidth
        guard needsCollapse, pendingCollapse == nil else {
            debugWorkspaceSidebarHoverLog("handleHoverExit noop panel=\(monitorScopeId) needsCollapse=\(needsCollapse) pendingCollapse=\(pendingCollapse != nil)")
            return
        }
        scheduleCollapse(collapsedWidth: collapsedWidth)
    }

    func scheduleCollapse(collapsedWidth: CGFloat) {
        debugWorkspaceSidebarHoverLog("scheduleCollapse panel=\(monitorScopeId) visible=\(viewModel.workspaceSidebarVisibleWidth) collapsed=\(collapsedWidth) mouse=\(NSEvent.mouseLocation)")
        NotificationCenter.default.post(name: workspaceSidebarWillCollapseNotification, object: nil)
        let collapse = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCollapse = nil
            debugWorkspaceSidebarHoverLog("collapseFire panel=\(self.monitorScopeId) visible=\(self.viewModel.workspaceSidebarVisibleWidth) mouse=\(NSEvent.mouseLocation) suppressActive=\(Date() < self.splitBrowseCollapseSuppressedUntil)")
            guard Date() >= self.splitBrowseCollapseSuppressedUntil else {
                debugWorkspaceSidebarHoverLog("collapseFire suppressed panel=\(self.monitorScopeId)")
                return
            }
            let inside = self.isMouseInsideHoverRegion()
            let locked = self.shouldLockExpansionForSidebarDrag()
            guard !inside, !locked else {
                debugWorkspaceSidebarHoverLog("collapseFire cancelled panel=\(self.monitorScopeId) inside=\(inside) locked=\(locked)")
                return
            }
            self.animateVisibleSidebarWidth(collapsedWidth, animation: .easeInOut(duration: self.animationDuration))
            self.scheduleCollapseFinalize()
        }
        pendingCollapse = collapse
        let collapseDelay: TimeInterval = viewModel.isWorkspaceSidebarExpanded ? 0.08 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: collapse)
    }

    func scheduleCollapseFinalize() {
        let finalize = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCollapseFinalize = nil
            debugWorkspaceSidebarHoverLog("collapseFinalize panel=\(self.monitorScopeId) visible=\(self.viewModel.workspaceSidebarVisibleWidth) mouse=\(NSEvent.mouseLocation) suppressActive=\(Date() < self.splitBrowseCollapseSuppressedUntil)")
            guard Date() >= self.splitBrowseCollapseSuppressedUntil else { return }
            let inside = self.isMouseInsideHoverRegion()
            let locked = self.shouldLockExpansionForSidebarDrag()
            guard !inside, !locked else {
                debugWorkspaceSidebarHoverLog("collapseFinalize cancelled panel=\(self.monitorScopeId) inside=\(inside) locked=\(locked)")
                return
            }
            viewModel.isWorkspaceSidebarExpanded = false
            self.updateMousePassthrough()
        }
        pendingCollapseFinalize = finalize
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration, execute: finalize)
    }
}
