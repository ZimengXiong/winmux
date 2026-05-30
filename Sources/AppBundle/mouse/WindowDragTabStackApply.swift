import Common

@MainActor
func createOrAppendWindowTabStack(sourceWindow: Window, onto targetWindow: Window) {
    guard sourceWindow != targetWindow else { return }
    let targetRect = normalizeTabStackSourceWindowFrame(sourceWindow: sourceWindow, targetWindow: targetWindow)
    if let targetParent = targetWindow.parent as? TilingContainer,
       targetParent.layout == .tabGroup
    {
        appendWindowToExistingTabGroup(
            sourceWindow: sourceWindow,
            targetWindow: targetWindow,
            targetParent: targetParent,
            targetRect: targetRect,
        )
        return
    }

    let targetBinding = targetWindow.unbindFromParent()
    let newOrientation = (targetBinding.parent as? TilingContainer)?.orientation.opposite ?? .h
    let newParent = TilingContainer(
        parent: targetBinding.parent,
        adaptiveWeight: targetBinding.adaptiveWeight,
        newOrientation,
        .tabGroup,
        index: targetBinding.index,
    )
    sourceWindow.unbindFromParent()
    targetWindow.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
    sourceWindow.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    if let targetRect {
        synchronizeTabbedWindowCache(targetWindow, rect: targetRect)
        synchronizeTabGroupCachedFrames(newParent, rect: targetRect)
    }
    sourceWindow.markAsMostRecentChild()
    _ = sourceWindow.focusWindow()
}

@MainActor
func reorderWindowTabInCurrentGroup(_ sourceWindow: Window, toIndex targetIndex: Int) -> Bool {
    guard let parent = sourceWindow.parent as? TilingContainer,
          parent.layout == .tabGroup,
          let currentIndex = sourceWindow.ownIndex
    else { return false }
    let clampedTarget = max(0, min(targetIndex, parent.children.count - 1))
    guard clampedTarget != currentIndex else { return true }
    let binding = sourceWindow.unbindFromParent()
    sourceWindow.bind(to: parent, adaptiveWeight: binding.adaptiveWeight, index: clampedTarget)
    sourceWindow.markAsMostRecentChild()
    _ = sourceWindow.focusWindow()
    return true
}

@MainActor
private func appendWindowToExistingTabGroup(
    sourceWindow: Window,
    targetWindow: Window,
    targetParent: TilingContainer,
    targetRect: Rect?,
) {
    if let targetRect {
        synchronizeTabbedWindowCache(targetWindow, rect: targetRect)
        synchronizeTabGroupCachedFrames(targetParent, rect: targetRect, excluding: sourceWindow.windowId)
    }
    let targetIndex = targetWindow.ownIndex.orDie()
    let sourceIndex = sourceWindow.ownIndex
    let sourceWasInTargetParent = sourceWindow.parent === targetParent
    sourceWindow.unbindFromParent()
    let insertIndex = if sourceWasInTargetParent, let sourceIndex {
        sourceIndex < targetIndex ? targetIndex : targetIndex + 1
    } else {
        targetIndex + 1
    }
    sourceWindow.bind(to: targetParent, adaptiveWeight: WEIGHT_AUTO, index: insertIndex)
    sourceWindow.markAsMostRecentChild()
    _ = sourceWindow.focusWindow()
}
