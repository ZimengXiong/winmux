import Foundation

@MainActor
func workspaceSidebarConfiguration() -> WorkspaceSidebarConfiguration {
    WorkspaceSidebarConfiguration(
        collapsedWidth: CGFloat(config.workspaceSidebar.collapsedWidth),
        expandedWidth: CGFloat(config.workspaceSidebar.width),
        topPadding: TrayMenuModel.shared.workspaceSidebarTopPadding,
        showMonitorSelector: TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector,
        showsClock: config.workspaceSidebar.showClock,
        showsSeconds: config.workspaceSidebar.showSeconds,
        showsDate: config.workspaceSidebar.showDate,
        showsWeekday: config.workspaceSidebar.showWeekday,
        showsStatusPills: config.workspaceSidebar.showStatusPills,
    )
}
