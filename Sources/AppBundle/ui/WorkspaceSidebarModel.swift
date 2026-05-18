import AppKit

@MainActor
func updateWorkspaceSidebarModel() async {
    guard TrayMenuModel.shared.isEnabled, config.workspaceSidebar.enabled else {
        clearWorkspaceSidebarModelState()
        return
    }

    let previousTopPadding = TrayMenuModel.shared.workspaceSidebarTopPadding
    pruneCachedWindowTitles()
    let state = await buildWorkspaceSidebarModelState(
        previousSelectedMonitorScopeId: TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId,
    )
    applyWorkspaceSidebarModelState(state, previousTopPadding: previousTopPadding)
}
