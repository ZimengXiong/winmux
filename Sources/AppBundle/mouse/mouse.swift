import AppKit

enum MouseManipulationKind: Equatable {
    case none
    case move
    case resize
}

private let postDragAxObserverSuppressionDuration: Duration = .seconds(2)

@MainActor var currentlyManipulatedWithMouseWindowId: UInt32? = nil
@MainActor private var pinnedDraggedWindowId: UInt32? = nil
@MainActor private var currentMouseDragSubject: WindowDragSubject = .window
@MainActor private var currentMouseTabDetachOrigin: TabDetachOrigin = .window
@MainActor private var currentMouseDragStartedInSidebar: Bool = false
@MainActor private var currentMouseManipulationKind: MouseManipulationKind = .none
@MainActor private var draggedWindowAnchorRectById: [UInt32: Rect] = [:]
@MainActor private var suppressedPostDragAxObserverEventsUntil: ContinuousClock.Instant? = nil
@MainActor private var suppressedPostDragAxObserverEventsByWindowId: [UInt32: ContinuousClock.Instant] = [:]

func isLeftMouseButtonPressed(mask: Int) -> Bool {
    (mask & 0x1) != 0
}

var isLeftMouseButtonDown: Bool { isLeftMouseButtonPressed(mask: NSEvent.pressedMouseButtons) }

@MainActor
func setPinnedDraggedWindowId(_ windowId: UInt32?) {
    pinnedDraggedWindowId = windowId
}

@MainActor
func isPinnedDraggedWindow(_ windowId: UInt32) -> Bool {
    pinnedDraggedWindowId == windowId
}

@MainActor
func hasPinnedDraggedWindow() -> Bool {
    pinnedDraggedWindowId != nil
}

@MainActor
func setCurrentMouseDragSubject(_ subject: WindowDragSubject) {
    currentMouseDragSubject = subject
}

@MainActor
func getCurrentMouseDragSubject() -> WindowDragSubject {
    currentMouseDragSubject
}

@MainActor
func setCurrentMouseTabDetachOrigin(_ origin: TabDetachOrigin) {
    currentMouseTabDetachOrigin = origin
}

@MainActor
func getCurrentMouseTabDetachOrigin() -> TabDetachOrigin {
    currentMouseTabDetachOrigin
}

@MainActor
func setCurrentMouseDragStartedInSidebar(_ startedInSidebar: Bool) {
    currentMouseDragStartedInSidebar = startedInSidebar
}

@MainActor
func getCurrentMouseDragStartedInSidebar() -> Bool {
    currentMouseDragStartedInSidebar
}

@MainActor
func setCurrentMouseManipulationKind(_ kind: MouseManipulationKind) {
    currentMouseManipulationKind = kind
}

@MainActor
func getCurrentMouseManipulationKind() -> MouseManipulationKind {
    currentMouseManipulationKind
}

@MainActor
func setDraggedWindowAnchorRect(_ rect: Rect?, for windowId: UInt32) {
    if let rect {
        draggedWindowAnchorRectById[windowId] = rect
    } else {
        draggedWindowAnchorRectById.removeValue(forKey: windowId)
    }
}

@MainActor
func draggedWindowAnchorRect(for windowId: UInt32) -> Rect? {
    draggedWindowAnchorRectById[windowId]
}

@MainActor
func clearDraggedWindowAnchorRect(for windowId: UInt32?) {
    guard let windowId else { return }
    draggedWindowAnchorRectById.removeValue(forKey: windowId)
}

@MainActor
func resolvedDraggedWindowAnchorRect(for window: Window, subject: WindowDragSubject) -> Rect? {
    switch subject {
        case .window:
            window.lastAppliedLayoutPhysicalRect ?? window.moveNode.lastAppliedLayoutPhysicalRect
        case .group:
            window.moveNode.lastAppliedLayoutPhysicalRect ?? window.lastAppliedLayoutPhysicalRect
    }
}

func currentSessionModifierFlags() -> CGEventFlags {
    CGEventSource.flagsState(.combinedSessionState)
}

func shouldPromoteWindowDragToTabGroupDrag(isOptionPressed: Bool, isTabbedWindow: Bool) -> Bool {
    isOptionPressed && isTabbedWindow
}

func shouldAllowSameWorkspaceWindowSurfaceIntent(
    enableWindowManagement: Bool,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    isOptionPressed: Bool,
) -> Bool {
    if enableWindowManagement {
        return true
    }
    if detachOrigin == .tabStrip {
        return true
    }
    return subject == .window && isOptionPressed
}

@MainActor
func isWindowInDraggableTabGroup(_ window: Window) -> Bool {
    guard let parent = window.parent as? TilingContainer else { return false }
    return parent.layout == .accordion && parent.children.count > 1
}

@MainActor
func shouldContinueCurrentGroupDrag(windowId: UInt32) -> Bool {
    getCurrentMouseManipulationKind() == .move &&
        currentlyManipulatedWithMouseWindowId == windowId &&
        getCurrentMouseDragSubject() == .group
}

@MainActor
func resolvedMouseDragSubject(for window: Window) -> WindowDragSubject {
    if shouldContinueCurrentGroupDrag(windowId: window.windowId) {
        return .group
    }
    let isOptionPressed = currentSessionModifierFlags().contains(.maskAlternate)
    return shouldPromoteWindowDragToTabGroupDrag(
        isOptionPressed: isOptionPressed,
        isTabbedWindow: isWindowInDraggableTabGroup(window),
    ) ? .group : .window
}

@MainActor
@discardableResult
func beginWindowMoveWithMouseSessionIfNeeded(
    windowId: UInt32,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    startedInSidebar: Bool,
    anchorRect: Rect?,
) -> Bool {
    let previousWindowId = currentlyManipulatedWithMouseWindowId
    let previousKind = getCurrentMouseManipulationKind()
    let previousSubject = getCurrentMouseDragSubject()
    let previousDetachOrigin = getCurrentMouseTabDetachOrigin()
    let previousStartedInSidebar = getCurrentMouseDragStartedInSidebar()

    if previousKind == .move,
       previousWindowId == windowId,
       previousSubject == subject,
       previousDetachOrigin == detachOrigin,
       previousStartedInSidebar == startedInSidebar
    {
        return false
    }

    if previousWindowId != windowId {
        clearDraggedWindowAnchorRect(for: previousWindowId)
    }

    currentlyManipulatedWithMouseWindowId = windowId
    setCurrentMouseManipulationKind(.move)
    setCurrentMouseDragSubject(subject)
    setCurrentMouseTabDetachOrigin(detachOrigin)
    setCurrentMouseDragStartedInSidebar(startedInSidebar)
    setDraggedWindowAnchorRect(anchorRect, for: windowId)
    WindowTabStripPanelController.shared.setIgnoresMouseEvents(true)
    refreshVisibleWindowActualRectsForCurrentDrag(sourceWindowId: windowId)
    return true
}

@MainActor
func cancelManipulatedWithMouseState() {
    cancelWindowDragActualRectRefresh()
    clearPendingUnmanagedWindowSnap()
    clearDraggedWindowAnchorRect(for: currentlyManipulatedWithMouseWindowId)
    setCurrentMouseManipulationKind(.none)
    setCurrentMouseDragSubject(.window)
    setCurrentMouseTabDetachOrigin(.window)
    setCurrentMouseDragStartedInSidebar(false)
    currentlyManipulatedWithMouseWindowId = nil
    WindowTabStripPanelController.shared.setIgnoresMouseEvents(false)
    for workspace in Workspace.all {
        workspace.resetResizeWeightBeforeResizeRecursive()
    }
}

@MainActor
func suppressPostDragAxObserverEvents(for windowIds: some Sequence<UInt32>) {
    let suppressionDeadline = ContinuousClock.now + postDragAxObserverSuppressionDuration
    for windowId in windowIds {
        suppressedPostDragAxObserverEventsByWindowId[windowId] = suppressionDeadline
    }
}

@MainActor
func armGlobalPostDragAxObserverSuppression() {
    suppressedPostDragAxObserverEventsUntil = ContinuousClock.now + postDragAxObserverSuppressionDuration
}

@MainActor
private func hasActiveGlobalPostDragAxObserverSuppression() -> Bool {
    guard let suppressionDeadline = suppressedPostDragAxObserverEventsUntil else { return false }
    if suppressionDeadline > ContinuousClock.now {
        return true
    }
    suppressedPostDragAxObserverEventsUntil = nil
    return false
}

@MainActor
private func hasActivePostDragAxObserverSuppression(for windowId: UInt32) -> Bool {
    guard let suppressionDeadline = suppressedPostDragAxObserverEventsByWindowId[windowId] else { return false }
    if suppressionDeadline > ContinuousClock.now {
        return true
    }
    suppressedPostDragAxObserverEventsByWindowId.removeValue(forKey: windowId)
    return false
}

@MainActor
func shouldIgnoreAxObserverEventForPostDragSuppression(windowId: UInt32?, notif: String) -> Bool {
    guard notif == kAXMovedNotification as String || notif == kAXResizedNotification as String else { return false }
    guard !isLeftMouseButtonDown else { return false }
    if hasActiveGlobalPostDragAxObserverSuppression() {
        debugFocusLog("axObserver.suppressed.global notif=\(notif) window=\(String(describing: windowId))")
        return true
    }
    guard let windowId else { return false }
    let shouldSuppress = hasActivePostDragAxObserverSuppression(for: windowId)
    if shouldSuppress {
        debugFocusLog("axObserver.suppressed window=\(windowId) notif=\(notif)")
    }
    return shouldSuppress
}

@MainActor
func isManipulatedWithMouse(_ window: Window) async throws -> Bool {
    try await (!window.isHiddenInCorner && // Don't allow to resize/move windows of hidden workspaces
        isLeftMouseButtonDown &&
        (currentlyManipulatedWithMouseWindowId == nil || window.windowId == currentlyManipulatedWithMouseWindowId))
        .andAsync { @Sendable @MainActor in try await getNativeFocusedWindow() == window }
}

func shouldIgnoreMovedObsForManagedWindowDragSession(
    observedWindowId: UInt32?,
    currentWindowId: UInt32?,
    kind: MouseManipulationKind,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    startedInSidebar: Bool,
) -> Bool {
    guard kind == .move,
          observedWindowId != nil,
          observedWindowId == currentWindowId
    else { return false }
    return startedInSidebar || detachOrigin == .tabStrip || subject == .group
}

@MainActor
func shouldIgnoreMovedObsForCurrentDragSession(windowId: UInt32?) -> Bool {
    shouldIgnoreMovedObsForManagedWindowDragSession(
        observedWindowId: windowId,
        currentWindowId: currentlyManipulatedWithMouseWindowId,
        kind: getCurrentMouseManipulationKind(),
        subject: getCurrentMouseDragSubject(),
        detachOrigin: getCurrentMouseTabDetachOrigin(),
        startedInSidebar: getCurrentMouseDragStartedInSidebar(),
    )
}

/// Same motivation as in monitorFrameNormalized
var mouseLocation: CGPoint {
    let mainMonitorHeight: CGFloat = mainMonitor.height
    let location = NSEvent.mouseLocation
    return location.copy(\.y, mainMonitorHeight - location.y)
}
