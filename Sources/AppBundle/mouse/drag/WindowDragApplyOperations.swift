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
    let matchingParent = targetNode.parentsWithSelf.lazy
        .compactMap { $0.parent as? TilingContainer }
        .first { parent in
            parent.layout == .tiles && parent.orientation == position.orientation
        }
    if let insertionParent = matchingParent,
       let anchorNode = targetNode.directChild(in: insertionParent) {
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
