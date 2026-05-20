import SwiftUI

extension WorkspaceSidebarPanel {
    func setHovering(_ isHovering: Bool) {
        let expandedWidth = CGFloat(config.workspaceSidebar.width)
        let collapsedWidth = CGFloat(config.workspaceSidebar.collapsedWidth)
        if isHovering {
            handleHoverEnter(expandedWidth: expandedWidth, collapsedWidth: collapsedWidth)
        } else {
            handleHoverExit(collapsedWidth: collapsedWidth)
        }
    }

    func shouldLockExpansionForSidebarDrag() -> Bool {
        shouldLockWorkspaceSidebarExpansion(
            hasDropPreview: TrayMenuModel.shared.workspaceSidebarDropPreview != nil,
            hasPinnedDraggedWindow: hasPinnedDraggedWindow(),
            isSidebarDragInProgress: getCurrentMouseManipulationKind() == .move && getCurrentMouseDragStartedInSidebar(),
            hasActiveEditor: isMenuTrackingOrInGracePeriod() || inlineTextEditingActive,
        ) || isMouseWindowDragInProgress()
    }
}
