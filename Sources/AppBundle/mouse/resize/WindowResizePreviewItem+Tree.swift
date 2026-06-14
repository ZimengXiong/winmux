import Common

extension WindowResizePreviewItem {
    @MainActor
    init(window: Window, rect: Rect, drawsFrameOnly: Bool = false) {
        let icon = WindowResizePreviewIcon(window: window)
        self.init(
            id: window.windowId,
            frame: rect.toAppKitScreenRect.alignedToBackingPixels(),
            appName: window.app.name ?? window.app.rawAppBundleId ?? "Window",
            icons: [icon],
            isTabGroup: false,
            drawsFrameOnly: drawsFrameOnly,
            frameOnlyHeaderHeight: 0,
        )
    }

    @MainActor
    init(tabGroup container: TilingContainer, rect: Rect, drawsFrameOnly: Bool = false) {
        let windows = container.childrenByMostRecentUse.compactMap(\.tabRepresentativeWindow)
        let representative = windows.first ?? container.tabRepresentativeWindow
        let icons = windows.map(WindowResizePreviewIcon.init(window:))
        let headerHeight = drawsFrameOnly ? windowTabBarRect(forGroupFrameRect: rect).height : 0
        self.init(
            id: representative?.windowId ?? UInt32(abs(ObjectIdentifier(container).hashValue) % Int(UInt32.max)),
            frame: rect.toAppKitScreenRect.alignedToBackingPixels(),
            appName: representative?.app.name ?? representative?.app.rawAppBundleId ?? "Tab Group",
            icons: icons,
            isTabGroup: true,
            drawsFrameOnly: drawsFrameOnly,
            frameOnlyHeaderHeight: headerHeight,
        )
    }
}
