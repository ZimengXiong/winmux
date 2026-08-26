import Foundation

@MainActor
func workspaceSidebarConfiguration() -> WorkspaceSidebarConfiguration {
    WorkspaceSidebarConfiguration(
        collapsedWidth: workspaceSidebarCollapsedContentWidth(config.workspaceSidebar),
        expandedWidth: CGFloat(config.workspaceSidebar.width),
        topPadding: TrayMenuModel.shared.workspaceSidebarTopPadding,
        showMonitorSelector: TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector,
        showsClock: config.workspaceSidebar.showClock,
        showsSeconds: config.workspaceSidebar.showSeconds,
        showsDate: config.workspaceSidebar.showDate,
        showsWeekday: config.workspaceSidebar.showWeekday,
        showsStatusPills: config.workspaceSidebar.showStatusPills,
        chromeStyle: config.workspaceSidebar.chromeStyle,
        solidChromeColor: config.workspaceSidebar.solidChromeColor,
        solidChromeCustomColor: config.workspaceSidebar.solidChromeCustomColor,
    )
}
