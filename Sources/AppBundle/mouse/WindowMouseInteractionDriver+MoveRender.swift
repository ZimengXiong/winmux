import AppKit

extension WindowMouseInteractionDriver {
    func renderMoveFrame(force: Bool) {
        guard let session = moveSession else { return }
        guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .move else { return }
        guard currentlyManipulatedWithMouseWindowId == session.windowId,
              let sourceWindow = Window.get(byId: session.windowId)
        else {
            clearPendingWindowDragIntent()
            clearPendingUnmanagedWindowSnap()
            stop()
            return
        }

        let mouse = MousePointerTracker.shared.currentSample.point
        updateCompositedMovePreview(sourceWindow: sourceWindow, mouseLocation: mouse)
        guard WindowDragFrameGate.shared.shouldProcess(
            windowId: sourceWindow.windowId,
            point: mouse,
            force: force,
        ) else { return }

        if config.enableWindowManagement {
            renderManagedMoveFrame(sourceWindow: sourceWindow, mouseLocation: mouse, session: session)
        } else {
            renderUnmanagedMoveFrame(sourceWindow: sourceWindow, mouseLocation: mouse, session: session)
        }
    }

    func renderManagedMoveFrame(sourceWindow: Window, mouseLocation: CGPoint, session: MoveSession) {
        switch sourceWindow.parent?.cases {
            case .workspace:
                moveFloatingWindowWithMouse(sourceWindow)
                clearPendingUnmanagedWindowSnap()
            case .tilingContainer:
                clearPendingUnmanagedWindowSnap()
                _ = updatePendingWindowDragIntent(
                    sourceWindow: sourceWindow,
                    mouseLocation: mouseLocation,
                    subject: session.subject,
                    detachOrigin: session.detachOrigin,
                )
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer, nil:
                clearPendingWindowDragIntent()
                clearPendingUnmanagedWindowSnap()
        }
    }
}
