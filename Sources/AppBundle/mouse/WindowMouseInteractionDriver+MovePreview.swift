import AppKit

extension WindowMouseInteractionDriver {
    func beginCompositedMovePreview(sourceWindow: Window, session: MoveSession) {
        guard session.subject == .group else {
            clearMovePreview()
            return
        }
        guard let anchorRect = draggedWindowAnchorRect(for: sourceWindow.windowId) ??
            resolvedDraggedWindowAnchorRect(for: sourceWindow, subject: session.subject),
            anchorRect.width > 0,
            anchorRect.height > 0
        else {
            clearMovePreview()
            return
        }
        let mouseLocation = MousePointerTracker.shared.currentSample.point
        dragSourcePreviewState = DragSourcePreviewState(
            windowId: sourceWindow.windowId,
            subject: session.subject,
            anchorRect: anchorRect,
            mouseOffset: CGPoint(x: mouseLocation.x - anchorRect.topLeftX, y: mouseLocation.y - anchorRect.topLeftY)
        )
        updateCompositedMovePreview(sourceWindow: sourceWindow, mouseLocation: mouseLocation)
    }

    func updateCompositedMovePreview(sourceWindow: Window, mouseLocation: CGPoint) {
        guard let state = dragSourcePreviewState,
              state.windowId == sourceWindow.windowId,
              state.subject == .group
        else { return }
        let frame = Rect(
            topLeftX: mouseLocation.x - state.mouseOffset.x,
            topLeftY: mouseLocation.y - state.mouseOffset.y,
            width: state.anchorRect.width,
            height: state.anchorRect.height,
        )
        guard let item = windowDragSourcePreviewItem(window: sourceWindow, subject: state.subject, frame: frame)
        else { return }
        if let stableFrame = windowResizePreviewAllScreensFrame() {
            WindowResizePreviewPanel.shared.beginStableFrame(stableFrame)
        } else {
            WindowResizePreviewPanel.shared.endStableFrame()
        }
        WindowResizePreviewPanel.shared.show([item])
    }
}
