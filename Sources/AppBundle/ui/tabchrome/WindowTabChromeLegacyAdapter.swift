import CoreGraphics

@MainActor
func windowTabBarFrame(fromGroupFrame groupFrame: CGRect) -> CGRect {
    let height = min(resolvedWindowTabBarHeight(), groupFrame.height)
    return CGRect(
        x: groupFrame.minX,
        y: groupFrame.maxY - height,
        width: groupFrame.width,
        height: height,
    ).alignedToBackingPixels()
}

extension WindowTabChromeTabItem {
    @MainActor
    func legacyTabItem(workspaceName: String) -> WindowTabItemViewModel {
        let window = Window.get(byId: id)
        return WindowTabItemViewModel(
            windowId: id,
            workspaceName: workspaceName,
            appName: appName,
            appBundleId: appBundleIdentifier,
            appBundlePath: window?.app.bundlePath,
            title: title,
            isActive: isActive,
        )
    }
}
