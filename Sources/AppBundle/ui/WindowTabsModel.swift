import AppKit

private let windowTabGroupShellHorizontalInsetValue: CGFloat = 3
private let windowTabGroupShellTopInsetValue: CGFloat = 0
private let windowTabGroupShellBottomInsetValue: CGFloat = 3
private let windowTabBarMinimumHeightValue: CGFloat = 36

func windowTabGroupShellHorizontalInset() -> CGFloat {
    windowTabGroupShellHorizontalInsetValue
}

func windowTabGroupShellTopInset() -> CGFloat {
    windowTabGroupShellTopInsetValue
}

func windowTabGroupShellBottomInset() -> CGFloat {
    windowTabGroupShellBottomInsetValue
}

@MainActor
func resolvedWindowTabBarHeight() -> CGFloat {
    max(CGFloat(config.windowTabs.height), windowTabBarMinimumHeightValue)
}

@MainActor
func windowTabGroupFrameRect(forActiveWindowContentRect contentRect: Rect) -> Rect {
    let horizontalInset = windowTabGroupShellHorizontalInset()
    let topInset = resolvedWindowTabBarHeight() + windowTabGroupShellTopInset()
    let bottomInset = windowTabGroupShellBottomInset()
    return Rect(
        topLeftX: contentRect.topLeftX - horizontalInset,
        topLeftY: contentRect.topLeftY - topInset,
        width: max(contentRect.width + horizontalInset * 2, 0),
        height: max(contentRect.height + topInset + bottomInset, 0),
    )
}

@MainActor
func windowTabBarRect(forGroupFrameRect groupFrameRect: Rect) -> Rect {
    Rect(
        topLeftX: groupFrameRect.topLeftX,
        topLeftY: groupFrameRect.topLeftY,
        width: groupFrameRect.width,
        height: min(resolvedWindowTabBarHeight(), groupFrameRect.height),
    )
}

@MainActor
func updateWindowTabModel() async {
    let didClearMouseInteractionChromeSuppression =
        WindowTabStripPanelController.shared.clearMouseInteractionChromeSuppressionIfInactive()
    guard TrayMenuModel.shared.isEnabled, config.windowTabs.enabled else {
        TrayMenuModel.shared.windowTabStrips = []
        WindowTabStripPanelController.shared.refresh()
        debugFocusLog("updateWindowTabModel disabled -> cleared")
        return
    }
    pruneCachedWindowTitles()

    var strips: [WindowTabStripViewModel] = []
    for workspace in Workspace.all where workspace.isVisible {
        if workspace.allLeafWindowsRecursive.contains(where: \.isFullscreen) {
            continue
        }
        let occludingFloatingWindowFrames = await windowTabOccludingFloatingWindowFrames(in: workspace)
        for container in workspace.rootTilingContainer.allTabbedContainersRecursive {
            guard let tabBarRect = container.windowTabBarRect,
                  let groupFrameRect = container.windowTabGroupFrameRect
            else { continue }
            let referenceRectSource = container.windowTabBarReferenceRectSource
            debugFocusLog(
                "updateWindowTabModel container=\(ObjectIdentifier(container)) workspace=\(workspace.name) containerRect=\(String(describing: container.lastAppliedLayoutPhysicalRect)) tabBarRect=\(tabBarRect) groupFrameRect=\(groupFrameRect) activeWindowId=\(String(describing: container.tabActiveWindow?.windowId)) referenceRectSource=\(referenceRectSource)"
            )

            let activeWindowId = container.tabActiveWindow?.windowId
            let tabs: [WindowTabItemViewModel] = await container.children.asyncCompactMap { child in
                guard let window = child.tabRepresentativeWindow else { return nil }
                let appName = window.app.name ?? window.app.rawAppBundleId ?? "Window"
                let title = await getCachedWindowTitle(window) ?? appName
                return WindowTabItemViewModel(
                    windowId: window.windowId,
                    workspaceName: workspace.name,
                    appName: appName,
                    appBundleId: window.app.rawAppBundleId,
                    appBundlePath: window.app.bundlePath,
                    title: title,
                    isActive: window.windowId == activeWindowId,
                )
            }
            guard !tabs.isEmpty else { continue }
            let appKitTabBarFrame = tabBarRect.toAppKitScreenRect.alignedToBackingPixels()
            let appKitGroupFrame = groupFrameRect.toAppKitScreenRect.alignedToBackingPixels()

            strips.append(
                WindowTabStripViewModel(
                    id: ObjectIdentifier(container),
                    workspaceName: workspace.name,
                    frame: appKitTabBarFrame,
                    groupFrame: appKitGroupFrame,
                    activeWindowId: activeWindowId,
                    activeWindowCornerRadius: windowTabGroupAppCornerRadius(activeWindowId: activeWindowId),
                    tabs: tabs,
                    occludingFloatingWindowFrames: occludingFloatingWindowFrames,
                ),
            )
        }
    }

    if TrayMenuModel.shared.windowTabStrips != strips {
        debugFocusLog("updateWindowTabModel apply strips old=\(TrayMenuModel.shared.windowTabStrips.map(\.frame)) new=\(strips.map(\.frame))")
        TrayMenuModel.shared.windowTabStrips = strips
        WindowTabStripPanelController.shared.refresh()
    } else {
        if didClearMouseInteractionChromeSuppression {
            WindowTabStripPanelController.shared.refresh()
        }
        debugFocusLog("updateWindowTabModel unchanged strips=\(strips.map(\.frame))")
    }
}

@MainActor
func windowTabOccludingFloatingWindowFrames(in workspace: Workspace) async -> [CGRect] {
    var frames: [CGRect] = []
    for window in workspace.floatingWindows where window.isBound {
        let rect: Rect?
        if let cachedRect = window.lastKnownActualRect {
            rect = cachedRect
        } else {
            rect = try? await window.getAxRect()
        }
        guard let rect, rect.width > 0, rect.height > 0 else { continue }
        frames.append(rect.toAppKitScreenRect.alignedToBackingPixels())
    }
    return frames
}

func windowTabLocalOcclusionRects(panelFrame: CGRect, occludingScreenFrames: [CGRect]) -> [CGRect] {
    occludingScreenFrames.compactMap { screenFrame in
        guard screenFrame.intersects(panelFrame) else { return nil }
        let local = CGRect(
            x: screenFrame.minX - panelFrame.minX,
            y: panelFrame.maxY - screenFrame.maxY,
            width: screenFrame.width,
            height: screenFrame.height,
        )
        let bounds = CGRect(origin: .zero, size: panelFrame.size)
        let clipped = local.intersection(bounds)
        guard clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }
}

func windowTabLocalFrame(panelFrame: CGRect, childFrame: CGRect) -> CGRect {
    CGRect(
        x: childFrame.minX - panelFrame.minX,
        y: panelFrame.maxY - childFrame.maxY,
        width: childFrame.width,
        height: childFrame.height,
    )
}

extension TreeNode {
    @MainActor
    var tabRepresentativeWindow: Window? {
        self as? Window ?? mostRecentWindowRecursive ?? anyLeafWindowRecursive
    }
}

extension TilingContainer {
    @MainActor
    var usesWindowTabBehavior: Bool {
        isWindowTabGroup && config.windowTabs.enabled
    }

    @MainActor
    var showsWindowTabs: Bool {
        usesWindowTabBehavior && tabActiveWindow?.isFullscreen != true
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
    private var windowTabBarReferenceRect: Rect? {
        if config.enableWindowManagement {
            return lastAppliedLayoutPhysicalRect
        }
        return tabActiveWindow?.lastKnownActualRect ??
            mostRecentWindowRecursive?.lastKnownActualRect ??
            anyLeafWindowRecursive?.lastKnownActualRect ??
            lastAppliedLayoutPhysicalRect
    }

    @MainActor
    fileprivate var windowTabBarReferenceRectSource: String {
        if config.enableWindowManagement {
            return "container.layout"
        }
        if tabActiveWindow?.lastKnownActualRect != nil {
            return "activeWindow.actual"
        }
        if mostRecentWindowRecursive?.lastKnownActualRect != nil {
            return "mostRecentWindow.actual"
        }
        if anyLeafWindowRecursive?.lastKnownActualRect != nil {
            return "anyLeafWindow.actual"
        }
        if lastAppliedLayoutPhysicalRect != nil {
            return "container.layout"
        }
        return "nil"
    }

    @MainActor
    var tabActiveWindow: Window? {
        mostRecentChild?.tabRepresentativeWindow ?? mostRecentWindowRecursive
    }

    @MainActor
    var allTabbedContainersRecursive: [TilingContainer] {
        var result: [TilingContainer] = []
        func visit(_ node: TreeNode) {
            guard let container = node as? TilingContainer else { return }
            if container.showsWindowTabs {
                result.append(container)
            }
            for child in container.children {
                visit(child)
            }
        }
        visit(self)
        return result
    }
}

extension Rect {
    var toAppKitScreenRect: CGRect {
        CGRect(
            x: minX,
            y: mainMonitor.height - topLeftY - height,
            width: width,
            height: height,
        )
    }
}

extension Sequence {
    fileprivate func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var result: [T] = []
        for element in self {
            if let transformed = await transform(element) {
                result.append(transformed)
            }
        }
        return result
    }
}
