import AppKit

extension TilingContainer {
    @MainActor
    var usesWindowTabBehavior: Bool {
        isWindowTabGroup && config.windowTabs.enabled
    }

    @MainActor
    var showsWindowTabs: Bool {
        usesWindowTabBehavior && !hasFullscreenTab
    }

    @MainActor
    var windowTabBarHeight: CGFloat {
        showsWindowTabs ? min(resolvedWindowTabBarHeight(), windowTabBarReferenceRect?.height ?? 0) : 0
    }

    @MainActor
    var windowTabBarRect: Rect? {
        guard showsWindowTabs, let rect = windowTabBarReferenceRect else { return nil }
        return Rect(topLeftX: rect.topLeftX, topLeftY: rect.topLeftY, width: rect.width, height: windowTabBarHeight)
    }

    @MainActor
    var windowTabGroupFrameRect: Rect? {
        guard showsWindowTabs else { return nil }
        return windowTabBarReferenceRect
    }

    @MainActor
    var tabActiveWindow: Window? {
        mostRecentChild?.tabRepresentativeWindow ?? mostRecentWindowRecursive
    }

    @MainActor
    var hasFullscreenTab: Bool {
        usesWindowTabBehavior && allLeafWindowsRecursive.contains(where: \.isFullscreen)
    }
}
