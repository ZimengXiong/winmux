import AppKit

extension WindowMouseInteractionDriver {
    func renderUnmanagedMoveFrame(sourceWindow: Window, mouseLocation: CGPoint, session: MoveSession) {
        let didUpdateIntent = updatePendingWindowDragIntent(
            sourceWindow: sourceWindow,
            mouseLocation: mouseLocation,
            subject: session.subject,
            detachOrigin: session.detachOrigin,
        )
        if didUpdateIntent {
            clearPendingUnmanagedWindowSnap()
        } else if session.subject == .window,
                  !session.startedInSidebar,
                  session.detachOrigin == .window
        {
            refreshPendingUnmanagedWindowSnap(sourceWindow: sourceWindow, mouseLocation: mouseLocation)
        } else {
            clearPendingUnmanagedWindowSnap()
        }
    }
}
