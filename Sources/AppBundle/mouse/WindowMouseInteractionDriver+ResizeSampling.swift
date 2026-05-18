import AppKit

extension WindowMouseInteractionDriver {
    func sampleResizeFrame(force: Bool) {
        guard let session = resizeSession else { return }
        guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .resize else { return }
        guard let window = Window.get(byId: session.windowId) else {
            stop()
            return
        }

        let sample = MousePointerTracker.shared.currentSample
        if var gesture = resizeGesture, gesture.windowId == session.windowId {
            let rect = gesture.predictedRect(mouse: sample.point)
            gesture.latestRect = rect
            resizeGesture = gesture
            updateResizePreviewIfNeeded(window: window, rect: rect, force: force)
            if force || sample.timestamp - gesture.lastCalibrationTimestamp >= resizeGestureCalibrationInterval {
                calibrateResizeGesture(window: window, session: session, force: false)
            }
            return
        }

        guard force || !isResizeSampleInFlight else { return }
        calibrateResizeGesture(window: window, session: session, force: force)
    }

    func finalResizeRect(for session: ResizeSession, window: Window) async -> Rect? {
        if let rect = try? await window.getAxRect() {
            return rect
        }
        if let resizeGesture, resizeGesture.windowId == session.windowId {
            return resizeGesture.predictedRect(mouse: MousePointerTracker.shared.currentSample.point)
        }
        return window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect
    }
}
