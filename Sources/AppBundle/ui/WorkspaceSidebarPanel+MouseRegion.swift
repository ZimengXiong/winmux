import AppKit

extension WorkspaceSidebarPanel {
    func updateMousePassthrough() {
        let shouldIgnoreMouseEvents = !isMouseInsideVisibleRegion()
        if ignoresMouseEvents != shouldIgnoreMouseEvents {
            ignoresMouseEvents = shouldIgnoreMouseEvents
        }
    }

    func isMouseInsideHoverRegion() -> Bool {
        guard isVisible else { return false }
        let hoverWidth = max(
            TrayMenuModel.shared.workspaceSidebarVisibleWidth,
            CGFloat(config.workspaceSidebar.collapsedWidth),
        ) + hoverExitTolerance
        let hoverRegion = NSRect(x: frame.minX, y: frame.minY, width: hoverWidth, height: frame.height)
        return hoverRegion.contains(NSEvent.mouseLocation)
    }

    func isMouseInsideVisibleRegion() -> Bool {
        guard isVisible else { return false }
        let visibleRegion = NSRect(
            x: frame.minX,
            y: frame.minY,
            width: TrayMenuModel.shared.workspaceSidebarVisibleWidth,
            height: frame.height,
        )
        return visibleRegion.contains(NSEvent.mouseLocation)
    }

    func isMouseDeepEnoughToExpand(collapsedWidth: CGFloat) -> Bool {
        guard isVisible else { return false }
        return isWorkspaceSidebarHoverDeepEnoughToExpand(
            mouseX: NSEvent.mouseLocation.x,
            sidebarMinX: frame.minX,
            collapsedWidth: collapsedWidth,
        )
    }
}
