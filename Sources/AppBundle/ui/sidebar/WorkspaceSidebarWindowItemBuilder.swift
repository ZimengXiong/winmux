@MainActor
func sidebarDisplayLabel(for window: Window) -> String {
    let appName = window.app.name ?? window.app.rawAppBundleId ?? "Unknown App"
    return cachedWindowTitle(for: window)?.takeIf { $0 != appName } ?? appName
}

@MainActor
func makeWorkspaceSidebarWindowViewModel(
    for window: Window,
    workspaceName: String,
    currentFocus: LiveFocus,
) async -> WorkspaceSidebarWindowViewModel {
    let appName = window.app.name ?? window.app.rawAppBundleId ?? "Unknown App"
    let title = await getSidebarWindowTitle(window, appName: appName)
    return WorkspaceSidebarWindowViewModel(
        windowId: window.windowId,
        workspaceName: workspaceName,
        appName: appName,
        title: title,
        isFocused: currentFocus.windowOrNil == window,
    )
}

@MainActor
private func getSidebarWindowTitle(_ window: Window, appName: String) async -> String? {
    await getCachedWindowTitle(window)?.takeIf { $0 != appName }
}
