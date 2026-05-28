import AppKit

extension WorkspaceSidebarPanel {
    func updateMousePassthrough() {
        let inside = isMouseInsideVisibleRegion()
        let shouldIgnoreMouseEvents = !inside
        if ignoresMouseEvents != shouldIgnoreMouseEvents {
            debugWorkspaceSidebarHoverLog("mousePassthrough panel=\(monitorScopeId) ignores \(ignoresMouseEvents)->\(shouldIgnoreMouseEvents) insideVisible=\(inside) visibleWidth=\(viewModel.workspaceSidebarVisibleWidth) frame=\(frame) mouse=\(NSEvent.mouseLocation)")
            ignoresMouseEvents = shouldIgnoreMouseEvents
        }
    }

    func isMouseInsideHoverRegion() -> Bool {
        guard isVisible else { return false }
        let hoverWidth = max(
            viewModel.workspaceSidebarVisibleWidth,
            CGFloat(config.workspaceSidebar.collapsedWidth),
        ) + hoverExitTolerance
        let hoverRegion = NSRect(x: frame.minX, y: frame.minY, width: hoverWidth, height: frame.height)
        let inside = hoverRegion.contains(NSEvent.mouseLocation)
        if viewModel.workspaceSidebarVisibleWidth > CGFloat(config.workspaceSidebar.collapsedWidth) + 0.5 || pendingCollapse != nil {
            debugWorkspaceSidebarHoverLog("hoverRegion panel=\(monitorScopeId) inside=\(inside) hoverWidth=\(hoverWidth) visibleWidth=\(viewModel.workspaceSidebarVisibleWidth) frame=\(frame) mouse=\(NSEvent.mouseLocation) suppressUntil=\(splitBrowseCollapseSuppressedUntil)")
        }
        return inside
    }

    func isMouseInsideVisibleRegion() -> Bool {
        guard isVisible else { return false }
        let visibleRegion = NSRect(
            x: frame.minX,
            y: frame.minY,
            width: viewModel.workspaceSidebarVisibleWidth,
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
