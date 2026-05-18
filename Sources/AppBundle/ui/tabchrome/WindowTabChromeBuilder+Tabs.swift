@MainActor
func makeWindowTabChromeTabs(
    container: TilingContainer,
    activeWindowId: UInt32,
) async -> [WindowTabChromeTabItem] {
    var tabs: [WindowTabChromeTabItem] = []
    for child in container.children {
        guard let window = child.tabRepresentativeWindow else { continue }
        tabs.append(await makeWindowTabChromeTab(window: window, activeWindowId: activeWindowId))
    }
    return tabs
}

@MainActor
private func makeWindowTabChromeTab(
    window: Window,
    activeWindowId: UInt32,
) async -> WindowTabChromeTabItem {
    let appName = window.app.name ?? window.app.rawAppBundleId ?? "Window"
    let title = await getCachedWindowTitle(window) ?? appName
    return WindowTabChromeTabItem(
        id: window.windowId,
        title: title,
        appName: appName,
        appBundleIdentifier: window.app.rawAppBundleId,
        isActive: window.windowId == activeWindowId,
    )
}
