import AppKit

enum MouseManipulationKind {
    case none
    case move
    case resize
}

@MainActor var currentlyManipulatedWithMouseWindowId: UInt32? = nil
@MainActor private var pinnedDraggedWindowId: UInt32? = nil
@MainActor private var currentMouseDragSubject: WindowDragSubject = .window
@MainActor private var currentMouseManipulationKind: MouseManipulationKind = .none
@MainActor private var draggedWindowAnchorRectById: [UInt32: Rect] = [:]
var isLeftMouseButtonDown: Bool { NSEvent.pressedMouseButtons == 1 }

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
func cancelManipulatedWithMouseState() {
    clearDraggedWindowAnchorRect(for: currentlyManipulatedWithMouseWindowId)
    setCurrentMouseManipulationKind(.none)
    setCurrentMouseDragSubject(.window)
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

/// Same motivation as in monitorFrameNormalized
var mouseLocation: CGPoint {
    let mainMonitorHeight: CGFloat = mainMonitor.height
    let location = NSEvent.mouseLocation
    return location.copy(\.y, mainMonitorHeight - location.y)
}
