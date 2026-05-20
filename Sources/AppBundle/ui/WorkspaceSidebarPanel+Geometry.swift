import AppKit

struct WorkspaceSidebarPanelLayout {
    let frame: NSRect
    let expandedWidth: CGFloat
    let collapsedWidth: CGFloat
}

extension WorkspaceSidebarPanel {
    func currentSidebarPanelLayout() -> WorkspaceSidebarPanelLayout? {
        guard TrayMenuModel.shared.isEnabled,
              config.workspaceSidebar.enabled,
              let screen = workspaceSidebarPanelScreen()
        else { return nil }
        guard !shouldSuppressChromeForFullscreenContent(on: workspaceSidebarResolvedPanelMonitor()) else { return nil }

        let sidebarConfig = config.workspaceSidebar
        let expandedWidth = CGFloat(sidebarConfig.width)
        let collapsedWidth = CGFloat(sidebarConfig.collapsedWidth)
        guard expandedWidth > 0, collapsedWidth > 0 else { return nil }

        let menuBarReserveHeight = min(CGFloat(sidebarConfig.menuBarReserveHeight), max(screen.frame.height - 1, 0))
        return WorkspaceSidebarPanelLayout(
            frame: NSRect(
                x: screen.frame.minX,
                y: screen.frame.minY,
                width: expandedWidth,
                height: screen.frame.height - menuBarReserveHeight,
            ),
            expandedWidth: expandedWidth,
            collapsedWidth: collapsedWidth,
        )
    }

    func workspaceSidebarPanelScreen() -> NSScreen? {
        NSScreen.screens.getOrNil(
            atIndex: workspaceSidebarResolvedPanelMonitor().monitorAppKitNsScreenScreensId - 1
        ) ?? NSScreen.screens.first
    }
}
