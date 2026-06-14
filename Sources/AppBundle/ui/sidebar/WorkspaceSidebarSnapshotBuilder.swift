import Foundation

@MainActor
func workspaceSidebarConfiguration() -> WorkspaceSidebarConfiguration {
    WorkspaceSidebarConfiguration(
        collapsedWidth: CGFloat(config.workspaceSidebar.collapsedWidth),
        expandedWidth: CGFloat(config.workspaceSidebar.width),
        topPadding: TrayMenuModel.shared.workspaceSidebarTopPadding,
        showMonitorSelector: TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector,
        showsDate: config.workspaceSidebar.showDate,
        showsStatusPills: config.workspaceSidebar.showStatusPills,
    )
}
