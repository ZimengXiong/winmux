import AppKit
import Common

@MainActor
struct WindowStackSplitContext {
    let insertionParent: TilingContainer?
    let anchorNode: TreeNode
    let wrapsTargetDirectly: Bool
}

@MainActor
func windowStackSplitContext(
    targetNode: TreeNode,
    position: WindowStackSplitPosition,
) -> WindowStackSplitContext? {
    if let insertionParent = targetNode.parentsWithSelf
        .lazy
        .compactMap({ $0.parent as? TilingContainer })
        .first(where: { $0.layout == .tiles && $0.orientation == position.orientation }),
       let anchorNode = targetNode.directChild(in: insertionParent)
    {
        return WindowStackSplitContext(
            insertionParent: insertionParent,
            anchorNode: anchorNode,
            wrapsTargetDirectly: false,
        )
    }
    guard targetNode.parent is TilingContainer || targetNode.parent is Workspace else { return nil }
    return WindowStackSplitContext(
        insertionParent: targetNode.parent as? TilingContainer,
        anchorNode: targetNode,
        wrapsTargetDirectly: true,
    )
}

@MainActor
func canOfferWindowStackSplit(
    sourceNode: TreeNode,
    targetNode: TreeNode,
    position: WindowStackSplitPosition,
) -> Bool {
    windowStackSplitContext(targetNode: targetNode, position: position) != nil
}

@MainActor
func resolvedWindowStackSplitPreview(targetNode: TreeNode, position: WindowStackSplitPosition) -> WindowStackSplitPreview? {
    guard let splitContext = windowStackSplitContext(targetNode: targetNode, position: position) else { return nil }
    let referenceNode = splitContext.wrapsTargetDirectly ? targetNode : splitContext.anchorNode
    guard let referenceRect = referenceNode.windowDragVisibleRect,
          let previewRect = referenceRect.stackSplitPreviewRect(position: position)
    else { return nil }
    return WindowStackSplitPreview(
        rect: previewRect,
        geometry: position.previewGeometry,
    )
}

@MainActor
func applyWindowStackSplitDragIntent(
    sourceWindow: Window,
    sourceSubject: WindowDragSubject,
    targetWindow: Window,
    position: WindowStackSplitPosition,
) -> Bool {
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: sourceSubject)
    let targetNode = dragIntentTargetNode(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: sourceSubject,
        detachOrigin: getCurrentMouseTabDetachOrigin(),
    )
    let splitOrientation = position.orientation
    guard !isBlockedByDragTargetContainment(sourceNode: sourceNode, targetNode: targetNode),
          !isInvalidGroupSelfTarget(sourceNode: sourceNode, targetNode: targetNode, subject: sourceSubject),
          canOfferWindowStackSplit(sourceNode: sourceNode, targetNode: targetNode, position: position),
          let splitContext = windowStackSplitContext(targetNode: targetNode, position: position)
    else { return false }

    sourceNode.unbindFromParent()
    if !splitContext.wrapsTargetDirectly {
        guard let insertionParent = splitContext.insertionParent else { return false }
        let anchorBinding = splitContext.anchorNode.unbindFromParent()
        let splitWeight = anchorBinding.adaptiveWeight / 2
        if position.isPositive {
            splitContext.anchorNode.bind(to: insertionParent, adaptiveWeight: splitWeight, index: anchorBinding.index)
            sourceNode.bind(to: insertionParent, adaptiveWeight: splitWeight, index: anchorBinding.index + 1)
        } else {
            sourceNode.bind(to: insertionParent, adaptiveWeight: splitWeight, index: anchorBinding.index)
            splitContext.anchorNode.bind(to: insertionParent, adaptiveWeight: splitWeight, index: anchorBinding.index + 1)
        }
    } else {
        let targetBinding = targetNode.unbindFromParent()
        let newParent = TilingContainer(
            parent: targetBinding.parent,
            adaptiveWeight: targetBinding.adaptiveWeight,
            splitOrientation,
            .tiles,
            index: targetBinding.index,
        )
        if position.isPositive {
            targetNode.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
            sourceNode.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        } else {
            sourceNode.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
            targetNode.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
    }
    return sourceWindow.focusWindow()
}

@MainActor
func applyWindowSwapDragIntent(
    sourceWindow: Window,
    sourceSubject: WindowDragSubject,
    targetWindow: Window,
) -> Bool {
    if shouldSuppressSameTabGroupSwapDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: sourceSubject,
        detachOrigin: getCurrentMouseTabDetachOrigin()
    ) {
        return false
    }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: sourceSubject)
    let targetNode = dragIntentTargetNode(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: sourceSubject,
        detachOrigin: getCurrentMouseTabDetachOrigin(),
    )
    guard !isBlockedByDragTargetContainment(sourceNode: sourceNode, targetNode: targetNode),
          !isInvalidGroupSelfTarget(sourceNode: sourceNode, targetNode: targetNode, subject: sourceSubject)
    else { return false }
    swapNodes(sourceNode, targetNode)
    return sourceWindow.focusWindow()
}

@MainActor
func expectedTabbedWindowRect(targetWindow: Window, targetRect: Rect) -> Rect {
    guard config.windowTabs.enabled else { return targetRect }
    let isAlreadyTabbed = (targetWindow.parent as? TilingContainer)?.layout == .tabGroup
    guard !isAlreadyTabbed else { return targetRect }

    let tabBarHeight = min(resolvedWindowTabBarHeight(), targetRect.height)
    return Rect(
        topLeftX: targetRect.topLeftX,
        topLeftY: targetRect.topLeftY + tabBarHeight,
        width: targetRect.width,
        height: max(targetRect.height - tabBarHeight, 0),
    )
}

@MainActor
func resolvedTabStackNormalizedRect(targetWindow: Window) -> Rect? {
    guard let rawTargetRect =
        currentWindowDragActualRect(targetWindow) ??
            targetWindow.lastKnownActualRect ??
            targetWindow.lastAppliedLayoutPhysicalRect
    else { return nil }
    return expectedTabbedWindowRect(targetWindow: targetWindow, targetRect: rawTargetRect)
}

@MainActor
func synchronizeTabbedWindowCache(_ window: Window, rect: Rect) {
    window.lastFloatingSize = rect.size
    window.lastKnownActualRect = rect
    window.lastAppliedLayoutPhysicalRect = rect
    windowDragActualRectCache[window.windowId] = rect
}

@MainActor
func normalizeTabStackSourceWindowFrame(sourceWindow: Window, targetWindow: Window) -> Rect? {
    guard let targetRect = resolvedTabStackNormalizedRect(targetWindow: targetWindow) else { return nil }
    synchronizeTabbedWindowCache(sourceWindow, rect: targetRect)
    sourceWindow.setAxFrame(targetRect.topLeftCorner, targetRect.size)
    return targetRect
}

@MainActor
func synchronizeTabGroupCachedFrames(_ container: TilingContainer, rect: Rect, excluding sourceWindowId: UInt32? = nil) {
    for case let window as Window in container.children where window.windowId != sourceWindowId {
        synchronizeTabbedWindowCache(window, rect: rect)
    }
}

@MainActor
func createOrAppendWindowTabStack(sourceWindow: Window, onto targetWindow: Window) {
    guard sourceWindow != targetWindow else { return }
    let targetRect = normalizeTabStackSourceWindowFrame(sourceWindow: sourceWindow, targetWindow: targetWindow)
    if let targetParent = targetWindow.parent as? TilingContainer,
       targetParent.layout == .tabGroup
    {
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
@discardableResult
func removeWindowFromTabStack(_ window: Window) -> Bool {
    guard let parent = window.parent as? TilingContainer, parent.layout == .tabGroup else {
        return false
    }

    if let grandParent = parent.parent as? TilingContainer {
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

    guard parent.parent is Workspace else { return false }
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
