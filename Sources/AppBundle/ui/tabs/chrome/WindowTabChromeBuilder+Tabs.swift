@MainActor
func makeWindowTabChromeTabs(
    container: TilingContainer,
    activeWindowId: UInt32,
) async -> [WindowTabChromeTabItem] {
    // Fetch tab titles concurrently: expired title-cache entries each cost an AX round-trip,
    // and fetching them serially makes the strip rebuild wait on the sum of them.
    let windows = container.children.compactMap(\.tabRepresentativeWindow)
    var tabsById: [UInt32: WindowTabChromeTabItem] = [:]
    await withTaskGroup(of: WindowTabChromeTabItem.self) { group in
        for window in windows {
            group.addTask { @Sendable @MainActor in
                await makeWindowTabChromeTab(window: window, activeWindowId: activeWindowId)
            }
        }
        for await tab in group {
            tabsById[tab.id] = tab
        }
    }
    return windows.compactMap { tabsById[$0.windowId] }
}

@MainActor
private func makeWindowTabChromeTab(
    window: Window,
    activeWindowId: UInt32,
) async -> WindowTabChromeTabItem {
    let appName = window.app.name ?? window.app.rawAppBundleId ?? "Window"
    let title = await getSessionWindowTitle(window) ?? appName
    return WindowTabChromeTabItem(
        id: window.windowId,
        title: title,
        appName: appName,
        appBundleIdentifier: window.app.rawAppBundleId,
        isActive: window.windowId == activeWindowId,
    )
}
