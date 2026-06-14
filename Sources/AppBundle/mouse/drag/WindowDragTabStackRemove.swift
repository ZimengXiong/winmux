@MainActor
@discardableResult
func removeWindowFromTabStack(_ window: Window) -> Bool {
    guard let parent = window.parent as? TilingContainer, parent.layout == .tabGroup else {
        return false
    }

    if let grandParent = parent.parent as? TilingContainer {
        return removeWindowFromNestedTabGroup(window, parent: parent, grandParent: grandParent)
    }

    guard parent.parent is Workspace else { return false }
    return removeWindowFromRootTabGroup(window, parent: parent)
}

@MainActor
private func removeWindowFromNestedTabGroup(
    _ window: Window,
    parent: TilingContainer,
    grandParent: TilingContainer,
) -> Bool {
    window.unbindFromParent()
    if parent.children.count == 1 {
        let parentBinding = parent.unbindFromParent()
        let remainingChild = parent.children.singleOrNil().orDie()
        remainingChild.unbindFromParent()
        remainingChild.bind(to: grandParent, adaptiveWeight: parentBinding.adaptiveWeight, index: parentBinding.index)
        window.bind(to: grandParent, adaptiveWeight: WEIGHT_AUTO, index: parentBinding.index + 1)
    } else {
        let parentIndex = parent.ownIndex.orDie()
        window.bind(to: grandParent, adaptiveWeight: WEIGHT_AUTO, index: parentIndex + 1)
    }
    window.markAsMostRecentChild()
    _ = window.focusWindow()
    return true
}

@MainActor
private func removeWindowFromRootTabGroup(_ window: Window, parent: TilingContainer) -> Bool {
    let remainingChildren = parent.children.filter { $0 != window }
    let tabGroupOrientation = parent.orientation

    window.unbindFromParent()
    let remainingMostRecentChild = parent.mostRecentChild
    parent.layout = .tiles
    parent.changeOrientation(tabGroupOrientation.opposite)

    if remainingChildren.count > 1 {
        let nestedTabGroup = TilingContainer(
            parent: parent,
            adaptiveWeight: WEIGHT_AUTO,
            tabGroupOrientation,
            .tabGroup,
            index: 0,
        )
        for child in remainingChildren {
            child.unbindFromParent()
            child.bind(to: nestedTabGroup, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
        remainingMostRecentChild?.markAsMostRecentChild()
    }

    window.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    window.markAsMostRecentChild()
    _ = window.focusWindow()
    return true
}
