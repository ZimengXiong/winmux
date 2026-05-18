import AppKit

extension WindowMouseInteractionDriver {
    func calibrateResizeGesture(window: Window, session: ResizeSession, force: Bool) {
        guard force || !isResizeSampleInFlight else { return }
        isResizeSampleInFlight = true
        let sessionWindowId = session.windowId
        let sample = MousePointerTracker.shared.currentSample
        Task { @MainActor in
            defer { isResizeSampleInFlight = false }
            guard resizeSession?.windowId == sessionWindowId, isLeftMouseButtonDown else { return }
            guard let rect = try? await window.getAxRect() else { return }
            guard resizeSession?.windowId == sessionWindowId, isLeftMouseButtonDown else { return }
            updateCalibratedResizeGesture(
                window: window,
                rect: rect,
                sessionWindowId: sessionWindowId,
                initialSample: sample,
            )
        }
    }

    func updateCalibratedResizeGesture(
        window: Window,
        rect: Rect,
        sessionWindowId: UInt32,
        initialSample: MousePointerSample,
    ) {
        let freshSample = MousePointerTracker.shared.currentSample
        if var gesture = resizeGesture, gesture.windowId == sessionWindowId {
            gesture.calibrate(observedRect: rect, mouse: freshSample.point, timestamp: freshSample.timestamp)
            resizeGesture = gesture
            updateResizePreviewIfNeeded(window: window, rect: gesture.predictedRect(mouse: freshSample.point))
        } else if let gesture = makeResizeGesture(window: window, observedRect: rect, sample: initialSample) {
            resizeGesture = gesture
            updateResizePreviewIfNeeded(window: window, rect: gesture.predictedRect(mouse: freshSample.point), force: true)
        } else {
            updateResizePreviewIfNeeded(window: window, rect: rect, force: true)
        }
    }
}
