@MainActor
func shouldDeferWindowTabStripGroupDragToDetachedTabDrag() -> Bool {
    getCurrentMouseManipulationKind() == .move &&
        getCurrentMouseDragSubject() == .window &&
        getCurrentMouseTabDetachOrigin() == .tabStrip
}

func isWindowTabStripDragInProgress(
    kind: MouseManipulationKind,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    startedInSidebar: Bool,
) -> Bool {
    guard kind == .move, !startedInSidebar else { return false }
    return detachOrigin == .tabStrip || subject == .group
}

@MainActor
func isWindowTabStripDragInProgress() -> Bool {
    isWindowTabStripDragInProgress(
        kind: getCurrentMouseManipulationKind(),
        subject: getCurrentMouseDragSubject(),
        detachOrigin: getCurrentMouseTabDetachOrigin(),
        startedInSidebar: getCurrentMouseDragStartedInSidebar(),
    )
}

func shouldShowCompositedGroupMovePreview(
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin = .window,
    startedInSidebar: Bool,
) -> Bool {
    subject == .group && detachOrigin != .tabStrip && !startedInSidebar
}

func shouldShowCompositedGroupMovePreview(session: WindowMouseInteractionDriver.MoveSession) -> Bool {
    shouldShowCompositedGroupMovePreview(
        subject: session.subject,
        detachOrigin: session.detachOrigin,
        startedInSidebar: session.startedInSidebar,
    )
}

@MainActor
func shouldHandleWindowTabStripGroupDragEnd() -> Bool {
    !shouldDeferWindowTabStripGroupDragToDetachedTabDrag()
}
