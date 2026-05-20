import AppKit

extension WindowMouseInteractionDriver {
    func sampleResizeFrame(force: Bool) {
        guard let session = resizeSession else {
            logWindowDragLive("resize.sample skipped reason=no-session force=\(force) mouseDown=\(isLeftMouseButtonDown) kind=\(getCurrentMouseManipulationKind())")
            return
        }
        guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .resize else {
            logWindowDragLive("resize.sample skipped reason=inactive session=\(session.windowId) force=\(force) mouseDown=\(isLeftMouseButtonDown) kind=\(getCurrentMouseManipulationKind())")
            return
        }
        guard let window = Window.get(byId: session.windowId) else {
            logWindowDragLive("resize.sample missing-window session=\(session.windowId); stopping driver")
            stop()
            return
        }

        let sample = MousePointerTracker.shared.currentSample
        if var gesture = resizeGesture, gesture.windowId == session.windowId {
            let rect = gesture.predictedRect(mouse: sample.point)
            logWindowDragLive("resize.sample predicted session=\(session.windowId) force=\(force) mouse=\(debugDescribe(sample.point)) rect=\(debugDescribe(rect))")
            gesture.latestRect = rect
            resizeGesture = gesture
            updateResizePreviewIfNeeded(window: window, rect: rect, force: force)
            if force || sample.timestamp - gesture.lastCalibrationTimestamp >= resizeGestureCalibrationInterval {
                calibrateResizeGesture(window: window, session: session, force: false)
            }
            return
        }

        guard force || !isResizeSampleInFlight else {
            logWindowDragLive("resize.sample skipped reason=calibration-in-flight session=\(session.windowId)")
            return
        }
        logWindowDragLive("resize.sample calibrating session=\(session.windowId) force=\(force)")
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
