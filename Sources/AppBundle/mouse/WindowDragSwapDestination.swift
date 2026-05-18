import AppKit

@MainActor
func swapDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint? = nil,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if shouldSuppressSameTabGroupSwapDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: subject,
        detachOrigin: detachOrigin
    ) {
        return nil
    }
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
          let previewRect = targetNode.swapDropZoneRect
    else { return nil }
    let interactionRect = if subject == .group {
        previewRect.expanded(left: 4, right: 4, top: 4, bottom: 6)
    } else {
        previewRect.expanded(left: 10, right: 10, top: 10, bottom: 10)
    }
    guard mouseLocation.map(interactionRect.contains) ?? true else { return nil }
    let isTabGroup = targetNode is TilingContainer
    return WindowDragIntentDestination(
        kind: .swap(targetWindowId: targetWindow.windowId),
        previewContainerRect: targetNode.windowDragVisibleRect ?? previewRect,
        previewRect: previewRect,
        interactionRect: interactionRect,
        title: isTabGroup ? "Swap With Tab Group" : "Swap Positions",
        subtitle: isTabGroup ? "Drop in the body to move around the whole group" : "Drop in the body to swap these windows",
        previewStyle: .swap,
        previewGeometry: .rounded,
        isGroup: subject == .group,
    )
}
