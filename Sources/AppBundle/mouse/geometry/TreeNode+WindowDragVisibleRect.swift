import Common

extension TreeNode {
    @MainActor
    var windowDragVisibleRect: Rect? {
        switch self {
            case let window as Window:
                return currentWindowDragActualRect(window) ?? window.lastAppliedLayoutPhysicalRect
            case let container as TilingContainer:
                if container.layout == .tabGroup {
                    let activeWindowRect = container.tabActiveWindow?.windowDragVisibleRect
                    let tabBarRect = container.windowTabBarRect
                    return Rect.union([activeWindowRect, tabBarRect].compactMap { $0 }) ?? container.lastAppliedLayoutPhysicalRect
                }
                let childRects = container.children.compactMap { $0.windowDragVisibleRect }
                return Rect.union(childRects) ?? container.lastAppliedLayoutPhysicalRect
            default:
                return lastAppliedLayoutPhysicalRect
        }
    }
}
