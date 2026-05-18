import AppKit

extension WindowMouseInteractionDriver {
    func makePendingResizeCandidate() async -> PendingResizeCandidate? {
        guard config.enableWindowManagement,
              getCurrentMouseManipulationKind() == .none,
              let window = try? await getNativeFocusedWindow(),
              window.parent is TilingContainer,
              !window.isHiddenInCorner
        else { return nil }
        let sample = MousePointerTracker.shared.currentSample
        guard cachedResizeCandidateIsViable(window: window, sample: sample) else { return nil }
        let cachedRect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect
        guard let observedRect = (try? await window.getAxRect()) ?? cachedRect else { return nil }
        let baseRect = window.lastAppliedLayoutPhysicalRect ?? observedRect
        let edges = resizeGestureCandidateEdges(mouse: sample.point, rect: observedRect)
        guard edges.hasAny else { return nil }
        return PendingResizeCandidate(
            windowId: window.windowId,
            baseRect: baseRect,
            observedRect: observedRect,
            edges: edges,
            mouseSample: sample,
        )
    }

    func cachedResizeCandidateIsViable(window: Window, sample: MousePointerSample) -> Bool {
        guard let cachedRect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect else { return true }
        return resizeGestureCandidateEdges(mouse: sample.point, rect: cachedRect).hasAny
    }
}
