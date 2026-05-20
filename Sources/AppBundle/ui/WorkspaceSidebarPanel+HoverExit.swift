import SwiftUI

extension WorkspaceSidebarPanel {
    func handleHoverExit(collapsedWidth: CGFloat) {
        pendingExpand?.cancel()
        pendingExpand = nil
        guard !shouldLockExpansionForSidebarDrag() else { return }
        let needsCollapse =
            viewModel.isWorkspaceSidebarExpanded ||
            viewModel.workspaceSidebarVisibleWidth != collapsedWidth
        guard needsCollapse, pendingCollapse == nil else { return }
        scheduleCollapse(collapsedWidth: collapsedWidth)
    }

    func scheduleCollapse(collapsedWidth: CGFloat) {
        NotificationCenter.default.post(name: workspaceSidebarWillCollapseNotification, object: nil)
        let collapse = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCollapse = nil
            guard !self.isMouseInsideHoverRegion(), !self.shouldLockExpansionForSidebarDrag() else { return }
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
            guard !self.isMouseInsideHoverRegion(), !self.shouldLockExpansionForSidebarDrag() else { return }
            viewModel.isWorkspaceSidebarExpanded = false
            self.updateMousePassthrough()
        }
        pendingCollapseFinalize = finalize
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration, execute: finalize)
    }
}
