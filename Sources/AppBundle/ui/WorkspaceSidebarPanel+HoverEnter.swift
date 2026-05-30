import SwiftUI

extension WorkspaceSidebarPanel {
    func handleHoverEnter(expandedWidth: CGFloat, collapsedWidth: CGFloat) {
        let cueWidth = workspaceSidebarHoverCueWidth(collapsedWidth: collapsedWidth, expandedWidth: expandedWidth)
        let isExpansionLocked = shouldLockExpansionForSidebarDrag()
        let isExternalWindowDrag = isMouseWindowDragInProgress()
        let isSidebarOriginatedDrag = getCurrentMouseDragStartedInSidebar()
        let shouldSuppressDragExpansion = shouldSuppressWorkspaceSidebarHoverExpansionForDrag(
            isSidebarItemDragActive: isWorkspaceSidebarItemDragActive(),
            isSidebarOriginatedDrag: isSidebarOriginatedDrag,
        )
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
        if shouldSuppressDragExpansion {
            pendingExpand?.cancel()
            pendingExpand = nil
            updateMousePassthrough()
            return
        }

        if isExternalWindowDrag && !isSidebarOriginatedDrag && isMousePushedAgainstDisplayEdge() {
            showCollapsedSidebarDuringExternalDrag(collapsedWidth: collapsedWidth)
            return
        }
        if !shouldDelayWorkspaceSidebarExpansion(
            isExpanded: viewModel.isWorkspaceSidebarExpanded,
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
        if viewModel.workspaceSidebarVisibleWidth != collapsedWidth {
            animateVisibleSidebarWidth(collapsedWidth, animation: .easeInOut(duration: animationDuration))
        } else {
            updateMousePassthrough()
        }
    }
}
