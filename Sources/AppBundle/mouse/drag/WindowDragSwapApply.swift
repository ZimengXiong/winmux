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
