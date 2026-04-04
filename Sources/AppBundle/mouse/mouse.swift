import AppKit

enum MouseManipulationKind: Equatable {
    case none
    case move
    case resize
}

@MainActor var currentlyManipulatedWithMouseWindowId: UInt32? = nil
@MainActor private var pinnedDraggedWindowId: UInt32? = nil
@MainActor private var currentMouseDragSubject: WindowDragSubject = .window
@MainActor private var currentMouseTabDetachOrigin: TabDetachOrigin = .window
@MainActor private var currentMouseDragStartedInSidebar: Bool = false
@MainActor private var currentMouseManipulationKind: MouseManipulationKind = .none
@MainActor private var draggedWindowAnchorRectById: [UInt32: Rect] = [:]

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
