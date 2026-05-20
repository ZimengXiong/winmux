import AppKit

extension WindowMouseInteractionDriver {
    func startDisplayLoop() {
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in
            self?.displayFrame()
        }
    }

    func displayFrame() {
        guard isLeftMouseButtonDown else {
            finishAfterMissedMouseUpIfNeeded()
            return
        }
        renderMoveFrame(force: false)
        sampleResizeFrame(force: false)
    }

    func finishAfterMissedMouseUpIfNeeded() {
        guard resizeSession != nil || moveSession != nil else {
            logWindowDragLive("resizePreview hide requested reason=displayLoop.idle mouseDown=\(isLeftMouseButtonDown)")
            DisplayRefreshDriver.shared.remove(owner: self)
            WindowResizePreviewPanel.shared.endStableFrame()
            WindowResizePreviewPanel.shared.hide(reason: "displayLoop.idle")
            return
        }
        guard !isMouseUpResetScheduled else { return }
        isMouseUpResetScheduled = true
        DisplayRefreshDriver.shared.remove(owner: self)
        Task { @MainActor in
            try? await resetManipulatedWithMouseIfPossible()
            isMouseUpResetScheduled = false
        }
    }
}
