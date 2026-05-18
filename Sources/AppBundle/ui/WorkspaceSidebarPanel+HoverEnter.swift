import SwiftUI

extension WorkspaceSidebarPanel {
    func handleHoverEnter(expandedWidth: CGFloat, collapsedWidth: CGFloat) {
        let cueWidth = workspaceSidebarHoverCueWidth(collapsedWidth: collapsedWidth, expandedWidth: expandedWidth)
        let isExpansionLocked = shouldLockExpansionForSidebarDrag()
        let isExternalWindowDrag = isMouseWindowDragInProgress()
        let isSidebarOriginatedDrag = getCurrentMouseDragStartedInSidebar()
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil

        if isExternalWindowDrag && !isSidebarOriginatedDrag && isMousePushedAgainstDisplayEdge() {
            showCollapsedSidebarDuringExternalDrag(collapsedWidth: collapsedWidth)
            return
        }
        if !shouldDelayWorkspaceSidebarExpansion(
            isExpanded: TrayMenuModel.shared.isWorkspaceSidebarExpanded,
            isExpansionLocked: isExpansionLocked,
            isMouseWindowDragInProgress: isExternalWindowDrag,
        ) {
            expandSidebar(to: expandedWidth)
            return
        }
        showHoverCue(cueWidth: cueWidth, expandedWidth: expandedWidth, collapsedWidth: collapsedWidth)
    }

    func showCollapsedSidebarDuringExternalDrag(collapsedWidth: CGFloat) {
        pendingExpand?.cancel()
        pendingExpand = nil
        if !isVisible {
            refresh()
        }
        if TrayMenuModel.shared.workspaceSidebarVisibleWidth != collapsedWidth {
            animateVisibleSidebarWidth(collapsedWidth, animation: .easeInOut(duration: animationDuration))
        } else {
            updateMousePassthrough()
        }
    }
}
