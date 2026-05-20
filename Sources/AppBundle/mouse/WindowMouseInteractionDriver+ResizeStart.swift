import AppKit

extension WindowMouseInteractionDriver {
    func startResize(windowId: UInt32) {
        let session = ResizeSession(windowId: windowId)
        let isNewSession = resizeSession != session
        logWindowDragLive("resize.start window=\(windowId) isNewSession=\(isNewSession) existingSession=\(String(describing: resizeSession)) mouseDown=\(isLeftMouseButtonDown) kind=\(getCurrentMouseManipulationKind())")
        if isNewSession {
            resetResizeTrackingState()
            clearPendingWindowDragIntent()
        }
        resizeSession = session
        currentlyManipulatedWithMouseWindowId = windowId
        WindowMouseInteractionOpacityController.shared.update(
            activeWindowId: windowId,
            hidesPassiveTabGroupChrome: true,
        )
        setCurrentMouseManipulationKind(.resize)
        configureResizeChrome(windowId: windowId)
        startDisplayLoop()
        sampleResizeFrame(force: true)
    }

    func configureResizeChrome(windowId: UInt32) {
        guard let window = Window.get(byId: windowId) else {
            logWindowDragLive("resize.configureChrome missing-window window=\(windowId)")
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction()
            return
        }
        let resizesTabGroup = windowResizeUsesActiveTabGroupChrome(window: window)
        logWindowDragLive("resize.configureChrome window=\(windowId) resizesTabGroup=\(resizesTabGroup) lastKnown=\(debugDescribe(window.lastKnownActualRect)) lastApplied=\(debugDescribe(window.lastAppliedLayoutPhysicalRect))")
        if resizesTabGroup {
            WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
        } else {
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: true)
        }
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
