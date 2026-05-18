import AppKit

extension WindowMouseInteractionDriver {
    func startMove(
        windowId: UInt32,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
        startedInSidebar: Bool,
    ) {
        let session = MoveSession(
            windowId: windowId,
            subject: subject,
            detachOrigin: detachOrigin,
            startedInSidebar: startedInSidebar,
        )
        let isNewSession = moveSession != session
        if isNewSession {
            WindowDragFrameGate.shared.reset(windowId: windowId)
        }
        moveSession = session
        WindowMouseInteractionOpacityController.shared.update(
            activeWindowId: windowId,
            hidesPassiveTabGroupChrome: session.startedInSidebar || session.subject == .group,
        )
        configureMoveChrome(windowId: windowId, session: session)
        startDisplayLoop()
        renderMoveFrame(force: isNewSession)
    }

    func configureMoveChrome(windowId: UInt32, session: MoveSession) {
        if session.startedInSidebar {
            clearMovePreview()
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: false)
        } else if shouldShowCompositedGroupMovePreview(session: session) {
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: false)
            if let sourceWindow = Window.get(byId: windowId) {
                beginCompositedMovePreview(sourceWindow: sourceWindow, session: session)
            }
        } else if session.detachOrigin == .tabStrip {
            clearMovePreview()
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction()
        } else {
            clearMovePreview()
            WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
        }
    }

    func clearMovePreview() {
        dragSourcePreviewState = nil
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide()
    }
}
