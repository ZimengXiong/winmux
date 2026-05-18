import AppKit

extension WindowMouseInteractionDriver {
    func startResize(windowId: UInt32) {
        let session = ResizeSession(windowId: windowId)
        if resizeSession != session {
            resetResizeTrackingState()
        }
        resizeSession = session
        currentlyManipulatedWithMouseWindowId = windowId
        WindowMouseInteractionOpacityController.shared.update(
            activeWindowId: windowId,
            hidesPassiveTabGroupChrome: true,
        )
        setCurrentMouseManipulationKind(.resize)
        clearPendingWindowDragIntent()
        clearPendingUnmanagedWindowSnap()
        configureResizeChrome(windowId: windowId)
        startDisplayLoop()
        sampleResizeFrame(force: true)
    }

    func configureResizeChrome(windowId: UInt32) {
        guard let window = Window.get(byId: windowId) else {
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction()
            return
        }
        let resizesTabGroup = window.nearestWindowTabGroup?.tabActiveWindow == window
        WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: !resizesTabGroup)
        if resizeGesture == nil {
            let sample = MousePointerTracker.shared.currentSample
            resizeGesture = makeResizeGesture(window: window, observedRect: window.lastKnownActualRect, sample: sample)
        }
        guard let rect = resizeGesture?.predictedRect(mouse: MousePointerTracker.shared.currentSample.point) ??
            window.lastAppliedLayoutPhysicalRect ??
            window.lastKnownActualRect
        else { return }
        beginStableResizePreviewFrame(for: window)
        updateResizePreviewIfNeeded(window: window, rect: rect, force: true)
    }

    func resetResizeTrackingState() {
        resizeGesture = nil
        isResizeSampleInFlight = false
        isMouseUpResetScheduled = false
        lastRenderedResizePreviewRect = nil
    }
}
