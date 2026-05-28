import SwiftUI

extension WorkspaceSidebarPanel {
    func setHovering(_ isHovering: Bool) {
        let expandedWidth = CGFloat(config.workspaceSidebar.width)
        let collapsedWidth = CGFloat(config.workspaceSidebar.collapsedWidth)
        if viewModel.workspaceSidebarVisibleWidth > collapsedWidth + 0.5 || pendingCollapse != nil {
            debugWorkspaceSidebarHoverLog("setHovering panel=\(monitorScopeId) isHovering=\(isHovering) visible=\(viewModel.workspaceSidebarVisibleWidth) frame=\(frame) mouse=\(NSEvent.mouseLocation)")
        }
        if isHovering {
            handleHoverEnter(
                expandedWidth: max(expandedWidth, viewModel.workspaceSidebarVisibleWidth),
                collapsedWidth: collapsedWidth
            )
        } else {
            handleHoverExit(collapsedWidth: collapsedWidth)
        }
    }

    func shouldLockExpansionForSidebarDrag() -> Bool {
        shouldLockWorkspaceSidebarExpansion(
            hasDropPreview: TrayMenuModel.shared.workspaceSidebarDropPreview != nil,
            hasPinnedDraggedWindow: hasPinnedDraggedWindow(),
            isSidebarDragInProgress: getCurrentMouseManipulationKind() == .move && getCurrentMouseDragStartedInSidebar(),
            hasActiveEditor: isMenuTrackingOrInGracePeriod() || shouldKeepSidebarOpenForInlineTextEditing(),
        ) || isMouseWindowDragInProgress()
    }

    func shouldKeepSidebarOpenForInlineTextEditing() -> Bool {
        commandExpansionLocksCollapse || (inlineTextEditingActive && inlineTextEditingLocksExpansion)
    }
}
