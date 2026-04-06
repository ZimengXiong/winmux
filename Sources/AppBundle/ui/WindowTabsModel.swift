import AppKit

@MainActor
func updateWindowTabModel() async {
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
        for container in workspace.rootTilingContainer.allTabbedContainersRecursive {
            guard let tabBarRect = container.windowTabBarRect else { continue }
            let referenceRectSource = container.windowTabBarReferenceRectSource
            debugFocusLog(
                "updateWindowTabModel container=\(ObjectIdentifier(container)) workspace=\(workspace.name) containerRect=\(String(describing: container.lastAppliedLayoutPhysicalRect)) tabBarRect=\(tabBarRect) activeWindowId=\(String(describing: container.tabActiveWindow?.windowId)) referenceRectSource=\(referenceRectSource)"
            )

            let activeWindowId = container.tabActiveWindow?.windowId
            let tabs: [WindowTabItemViewModel] = await container.children.asyncCompactMap { child in
                guard let window = child.tabRepresentativeWindow else { return nil }
                let appName = window.app.name ?? window.app.rawAppBundleId ?? "Window"
                let title = await getCachedWindowTitle(window) ?? appName
                return WindowTabItemViewModel(
                    windowId: window.windowId,
                    workspaceName: workspace.name,
                    title: title,
                    isActive: window.windowId == activeWindowId,
                )
            }
            guard !tabs.isEmpty else { continue }

            strips.append(
                WindowTabStripViewModel(
                    id: ObjectIdentifier(container),
                    workspaceName: workspace.name,
                    frame: tabBarRect.toAppKitScreenRect,
                    tabs: tabs,
                ),
            )
        }
    }

    if TrayMenuModel.shared.windowTabStrips != strips {
        debugFocusLog("updateWindowTabModel apply strips old=\(TrayMenuModel.shared.windowTabStrips.map(\.frame)) new=\(strips.map(\.frame))")
        TrayMenuModel.shared.windowTabStrips = strips
        WindowTabStripPanelController.shared.refresh()
    } else {
        debugFocusLog("updateWindowTabModel unchanged strips=\(strips.map(\.frame))")
    }
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
        showsWindowTabs ? min(CGFloat(config.windowTabs.height), windowTabBarReferenceRect?.height ?? 0) : 0
    }

    @MainActor
    var windowTabBarRect: Rect? {
        guard showsWindowTabs, let rect = windowTabBarReferenceRect else { return nil }
        return Rect(topLeftX: rect.topLeftX, topLeftY: rect.topLeftY, width: rect.width, height: windowTabBarHeight)
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
