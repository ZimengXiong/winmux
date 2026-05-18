import AppKit

@MainActor
func stackSplitDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint? = nil,
    subject: WindowDragSubject,
    position: WindowStackSplitPosition,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if shouldSuppressSwapDestination(sourceWindow: sourceWindow, subject: subject) {
        return nil
    }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetNode = dragIntentTargetNode(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: subject,
        detachOrigin: detachOrigin,
    )
    guard !isBlockedByDragTargetContainment(sourceNode: sourceNode, targetNode: targetNode),
          !isInvalidGroupSelfTarget(sourceNode: sourceNode, targetNode: targetNode, subject: subject),
          canOfferWindowStackSplit(sourceNode: sourceNode, targetNode: targetNode, position: position),
          let preview = resolvedWindowStackSplitPreview(targetNode: targetNode, position: position),
          let interactionRect = targetNode.stackSplitDropZoneRect(position: position)?
          .expanded(left: subject == .group ? 4 : 10, right: subject == .group ? 4 : 10, top: 0, bottom: 0)
    else { return nil }
    guard mouseLocation.map(interactionRect.contains) ?? true else { return nil }
    return WindowDragIntentDestination(
        kind: .stackSplit(targetWindowId: targetWindow.windowId, position: position),
        previewContainerRect: targetNode.windowDragVisibleRect ?? preview.rect,
        previewRect: preview.rect,
        interactionRect: interactionRect,
        title: position.title,
        subtitle: position.subtitle,
        previewStyle: .stackSplit,
        previewGeometry: preview.geometry,
        isGroup: subject == .group,
    )
}
