import AppKit

struct WorkspaceSidebarPanelLayout {
    let frame: NSRect
    let expandedWidth: CGFloat
    let collapsedWidth: CGFloat
}

extension WorkspaceSidebarPanel {
    func currentSidebarPanelLayout() -> WorkspaceSidebarPanelLayout? {
        currentSidebarPanelLayout(on: workspaceSidebarResolvedPanelMonitor())
    }

    func currentSidebarPanelLayout(on monitor: Monitor) -> WorkspaceSidebarPanelLayout? {
        guard TrayMenuModel.shared.isEnabled,
              config.workspaceSidebar.enabled,
              let screen = workspaceSidebarPanelScreen(for: monitor)
        else { return nil }
        guard !shouldSuppressWorkspaceSidebarForFullscreenContent() else { return nil }

        let sidebarConfig = config.workspaceSidebar
        let expandedWidth = CGFloat(sidebarConfig.width)
        let maximumExpandedWidth = expandedWidth * 2
        let collapsedWidth = CGFloat(sidebarConfig.collapsedWidth)
        guard expandedWidth > 0, collapsedWidth > 0 else { return nil }

        let menuBarReserveHeight = min(CGFloat(sidebarConfig.menuBarReserveHeight), max(screen.frame.height - 1, 0))
        return WorkspaceSidebarPanelLayout(
            frame: NSRect(
                x: screen.frame.minX,
                y: screen.frame.minY,
                width: maximumExpandedWidth,
                height: screen.frame.height - menuBarReserveHeight,
            ),
            expandedWidth: expandedWidth,
            collapsedWidth: collapsedWidth,
        )
    }

    func workspaceSidebarPanelScreen() -> NSScreen? {
        workspaceSidebarPanelScreen(for: workspaceSidebarResolvedPanelMonitor())
    }

    func workspaceSidebarPanelScreen(for monitor: Monitor) -> NSScreen? {
        NSScreen.screens.getOrNil(
            atIndex: monitor.monitorAppKitNsScreenScreensId - 1
        ) ?? NSScreen.screens.first
    }
}
