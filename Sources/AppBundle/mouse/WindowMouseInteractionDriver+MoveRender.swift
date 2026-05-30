import AppKit

extension WindowMouseInteractionDriver {
    func renderMoveFrame(force: Bool) {
        guard let session = moveSession else { return }
        guard (isLeftMouseButtonDown || force), getCurrentMouseManipulationKind() == .move else { return }
        guard currentlyManipulatedWithMouseWindowId == session.windowId,
              let sourceWindow = Window.get(byId: session.windowId)
        else {
            clearPendingWindowDragIntent()
            stop()
            return
        }

        let mouse = MousePointerTracker.shared.currentSample.point
        updateCompositedMovePreview(sourceWindow: sourceWindow, mouseLocation: mouse)
        let isPointerInsideSidebar = WorkspaceSidebarPanel.panel(containing: mouse) != nil
        let shouldProcess = session.startedInSidebar || isPointerInsideSidebar || WindowDragFrameGate.shared.shouldProcess(
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

        renderManagedMoveFrame(sourceWindow: sourceWindow, mouseLocation: mouse, session: session)
    }

    func renderManagedMoveFrame(sourceWindow: Window, mouseLocation: CGPoint, session: MoveSession) {
        if WorkspaceSidebarPanel.panel(containing: mouseLocation) != nil {
            _ = updatePendingWindowDragIntent(
                sourceWindow: sourceWindow,
                mouseLocation: mouseLocation,
                subject: session.subject,
                detachOrigin: session.detachOrigin,
            )
            return
        }
        if session.startedInSidebar {
            refreshActiveWorkspaceSidebarDragPreviewIfNeeded()
            _ = updatePendingWindowDragIntent(
                sourceWindow: sourceWindow,
                mouseLocation: mouseLocation,
                subject: session.subject,
                detachOrigin: session.detachOrigin,
            )
            return
        }
        switch sourceWindow.parent?.cases {
            case .workspace:
                moveFloatingWindowWithMouse(sourceWindow)
            case .tilingContainer:
                _ = updatePendingWindowDragIntent(
                    sourceWindow: sourceWindow,
                    mouseLocation: mouseLocation,
                    subject: session.subject,
                    detachOrigin: session.detachOrigin,
                )
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer, nil:
                clearPendingWindowDragIntent()
        }
    }
}
