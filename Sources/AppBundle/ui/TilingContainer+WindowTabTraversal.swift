extension TilingContainer {
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

    @MainActor
    var windowTabBarReferenceRect: Rect? {
        lastAppliedLayoutPhysicalRect
    }
}
