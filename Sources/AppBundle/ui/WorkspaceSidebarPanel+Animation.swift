import SwiftUI

extension WorkspaceSidebarPanel {
    func animateVisibleSidebarWidth(_ width: CGFloat, animation: Animation) {
        withAnimation(animation) {
            viewModel.workspaceSidebarVisibleWidth = width
        }
        updateMousePassthrough()
    }

    func expandSidebar(to expandedWidth: CGFloat) {
        pendingExpand?.cancel()
        pendingExpand = nil
        NotificationCenter.default.post(name: workspaceSidebarWillExpandNotification, object: nil)
        viewModel.isWorkspaceSidebarExpanded = true
        if !isVisible {
            refresh()
        }
        guard viewModel.workspaceSidebarVisibleWidth != expandedWidth else {
            updateMousePassthrough()
            return
        }
        animateVisibleSidebarWidth(expandedWidth, animation: .easeInOut(duration: animationDuration))
    }

    func cancelExpansionWork() {
        pendingExpand?.cancel()
        pendingExpand = nil
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
    }
}
