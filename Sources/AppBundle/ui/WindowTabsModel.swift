import AppKit

@MainActor
func updateWindowTabModel() async {
    guard TrayMenuModel.shared.isEnabled, config.windowTabs.enabled else {
        TrayMenuModel.shared.windowTabStrips = []
        WindowTabStripPanelController.shared.refresh()
        return
    }

    var strips: [WindowTabStripViewModel] = []
    for workspace in Workspace.all where workspace.isVisible {
        if workspace.allLeafWindowsRecursive.contains(where: \.isFullscreen) {
            continue
        }
        for container in workspace.rootTilingContainer.allTabbedContainersRecursive {
            guard let tabBarRect = container.windowTabBarRect else { continue }

            let activeWindowId = container.tabActiveWindow?.windowId
            let tabs: [WindowTabItemViewModel] = await container.children.asyncCompactMap { child in
                guard let window = child.tabRepresentativeWindow else { return nil }
                let appName = window.app.name ?? window.app.rawAppBundleId ?? "Window"
                let rawTitle = try? await window.title
                let title = rawTitle?.takeIf { !$0.isEmpty } ?? appName
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
        TrayMenuModel.shared.windowTabStrips = strips
        WindowTabStripPanelController.shared.refresh()
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
        layout == .accordion && config.windowTabs.enabled && children.count > 1
    }

    @MainActor
    var showsWindowTabs: Bool {
        usesWindowTabBehavior && tabActiveWindow?.isFullscreen != true
    }

    @MainActor
    var windowTabBarHeight: CGFloat {
        showsWindowTabs ? min(CGFloat(config.windowTabs.height), lastAppliedLayoutPhysicalRect?.height ?? 0) : 0
    }

    @MainActor
    var windowTabBarRect: Rect? {
        guard showsWindowTabs, let rect = lastAppliedLayoutPhysicalRect else { return nil }
        return Rect(topLeftX: rect.topLeftX, topLeftY: rect.topLeftY, width: rect.width, height: windowTabBarHeight)
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
