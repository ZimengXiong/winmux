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
        let shouldProcess = WindowDragFrameGate.shared.shouldProcess(
            windowId: sourceWindow.windowId,
            point: mouse,
            force: force,
        )
        let gateState = WindowDragFrameGate.shared.state(for: sourceWindow.windowId)
        logWindowDragHitTestIfNeeded(
            signature: "drag-live:frame:window=\(sourceWindow.windowId):bucket=\(debugDescribeDragPointBucket(mouse)):process=\(shouldProcess):settled=\(gateState?.isSettled.description ?? "nil")",
            "[drag-live] frame window=\(sourceWindow.windowId) subject=\(debugDescribe(session.subject)) origin=\(session.detachOrigin) mouse=\(debugDescribe(mouse)) bucket=\(debugDescribeDragPointBucket(mouse)) shouldProcess=\(shouldProcess) velocity=\(gateState?.velocity.description ?? "nil") settled=\(gateState?.isSettled.description ?? "nil") force=\(force)"
        )
        guard shouldProcess else { return }

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
