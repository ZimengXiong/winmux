import AppKit

extension WindowMouseInteractionDriver {
    func capturePendingResizeCandidate() async {
        guard let candidate = await makePendingResizeCandidate() else {
            pendingResizeCandidate = nil
            return
        }
        pendingResizeCandidate = candidate
    }

    func makeResizeGesture(window: Window, observedRect: Rect?, sample: MousePointerSample) -> ResizeGestureSessionState? {
        guard let observedRect = observedRect ?? window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect else { return nil }
        if let pendingResizeCandidate,
           pendingResizeCandidate.windowId == window.windowId
        {
            return makeResizeGestureSession(
                windowId: window.windowId,
                baseRect: pendingResizeCandidate.baseRect,
                observedRect: pendingResizeCandidate.observedRect,
                mouse: pendingResizeCandidate.mouseSample.point,
                edges: pendingResizeCandidate.edges,
                timestamp: pendingResizeCandidate.mouseSample.timestamp,
            )
        }
        return makeResizeGestureFromObservedRect(window: window, observedRect: observedRect, sample: sample)
    }

    func makeResizeGestureFromObservedRect(
        window: Window,
        observedRect: Rect,
        sample: MousePointerSample,
    ) -> ResizeGestureSessionState? {
        let baseRect = window.lastAppliedLayoutPhysicalRect ?? observedRect
        return makeResizeGestureSession(
            windowId: window.windowId,
            baseRect: baseRect,
            observedRect: observedRect,
            mouse: sample.point,
            edges: resizeGestureEdges(baseRect: baseRect, observedRect: observedRect, mouse: sample.point),
            timestamp: sample.timestamp,
        )
    }
}
