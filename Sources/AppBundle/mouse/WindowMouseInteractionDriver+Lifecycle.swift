import AppKit

extension WindowMouseInteractionDriver {
    func noteGlobalDragActivity() {
        if moveSession != nil {
            renderMoveFrame(force: false)
        }
        if resizeSession != nil {
            sampleResizeFrame(force: false)
        }
    }

    func flushBeforeMouseUp() async {
        if moveSession != nil {
            renderMoveFrame(force: true)
        }
        guard let resizeSession else { return }
        defer { finishResizeFlush(session: resizeSession) }
        guard let window = Window.get(byId: resizeSession.windowId) else { return }
        guard let rect = await finalResizeRect(for: resizeSession, window: window) else { return }
        guard self.resizeSession == resizeSession else { return }
        updateResizePreviewIfNeeded(window: window, rect: rect, force: true)
        applyResizeWithMouse(window, rect: rect)
    }

    func stop() {
        logWindowDragLive("driver.stop moveSession=\(String(describing: moveSession)) resizeSession=\(String(describing: resizeSession)) manipulated=\(currentlyManipulatedWithMouseWindowId?.description ?? "nil") kind=\(getCurrentMouseManipulationKind()) mouseDown=\(isLeftMouseButtonDown)")
        DisplayRefreshDriver.shared.remove(owner: self)
        moveSession = nil
        resizeSession = nil
        dragSourcePreviewState = nil
        pendingResizeCandidate = nil
        resetResizeTrackingState()
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "driver.stop")
        WindowMouseInteractionOpacityController.shared.restore()
        WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
    }

    func finishResizeFlush(session: ResizeSession) {
        if resizeSession == session {
            resizeSession = nil
        }
        pendingResizeCandidate = nil
        resetResizeTrackingState()
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "driver.finishResizeFlush")
    }
}
