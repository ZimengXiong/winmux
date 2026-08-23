import Common

@MainActor
func expectedTabbedWindowRect(targetWindow: Window, targetRect: Rect) -> Rect {
    guard config.windowTabs.enabled else { return targetRect }
    let isAlreadyTabbed = (targetWindow.parent as? TilingContainer)?.layout == .tabGroup
    guard !isAlreadyTabbed else { return targetRect }

    let tabBarHeight = min(resolvedWindowTabBarHeight(), targetRect.height)
    return Rect(
        topLeftX: targetRect.topLeftX,
        topLeftY: targetRect.topLeftY + tabBarHeight,
        width: targetRect.width,
        height: max(targetRect.height - tabBarHeight, 0),
    )
}

@MainActor
func resolvedTabStackNormalizedRect(targetWindow: Window) -> Rect? {
    if let parent = targetWindow.parent as? TilingContainer,
       parent.layout == .tabGroup,
       let tabContentRect = parent.tabStackContentRect
    {
        return tabContentRect
    }
    guard let rawTargetRect =
        currentWindowDragActualRect(targetWindow) ??
            targetWindow.lastKnownActualRect ??
            targetWindow.lastAppliedLayoutPhysicalRect
    else { return nil }
    return expectedTabbedWindowRect(targetWindow: targetWindow, targetRect: rawTargetRect)
}

private extension TilingContainer {
    @MainActor
    var tabStackContentRect: Rect? {
        guard usesWindowTabBehavior,
              let groupRect = lastAppliedLayoutPhysicalRect
        else {
            return tabActiveWindow?.lastAppliedLayoutPhysicalRect
        }
        let tabBarHeight = showsWindowTabs ? windowTabBarHeight : 0
        let shellHorizontalInset = showsWindowTabs ? windowTabGroupShellHorizontalInset() : 0
        let shellTopInset = showsWindowTabs ? windowTabGroupShellTopInset() : 0
        let shellBottomInset = showsWindowTabs ? windowTabGroupShellBottomInset() : 0
        return Rect(
            topLeftX: groupRect.topLeftX + shellHorizontalInset,
            topLeftY: groupRect.topLeftY + tabBarHeight + shellTopInset,
            width: max(groupRect.width - shellHorizontalInset * 2, 0),
            height: max(groupRect.height - tabBarHeight - shellTopInset - shellBottomInset, 0),
        )
    }
}

@MainActor
func synchronizeTabbedWindowCache(_ window: Window, rect: Rect) {
    window.lastFloatingSize = rect.size
    window.recordAuthoritativeActualRect(rect)
    window.lastAppliedLayoutPhysicalRect = rect
    windowDragActualRectCache[window.windowId] = rect
}

@MainActor
func normalizeTabStackSourceWindowFrame(sourceWindow: Window, targetWindow: Window) -> Rect? {
    guard let targetRect = resolvedTabStackNormalizedRect(targetWindow: targetWindow) else { return nil }
    synchronizeTabbedWindowCache(sourceWindow, rect: targetRect)
    sourceWindow.setAxFrame(targetRect.topLeftCorner, targetRect.size)
    return targetRect
}

@MainActor
func synchronizeTabGroupCachedFrames(_ container: TilingContainer, rect: Rect, excluding sourceWindowId: UInt32? = nil) {
    for case let window as Window in container.children where window.windowId != sourceWindowId {
        synchronizeTabbedWindowCache(window, rect: rect)
    }
}
