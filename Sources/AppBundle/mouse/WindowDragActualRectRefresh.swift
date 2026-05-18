@MainActor
func refreshVisibleWindowActualRectsForCurrentDrag(sourceWindowId: UInt32) {
    windowDragActualRectRefreshTask?.cancel()
    windowDragActualRectRefreshTask = Task { @MainActor in
        let visibleWindows = Workspace.all
            .filter(\.isVisible)
            .flatMap(\.allLeafWindowsRecursive)
        cacheCurrentActualRects(visibleWindows)
        await refreshActualRects(visibleWindows, sourceWindowId: sourceWindowId)
        guard currentlyManipulatedWithMouseWindowId == sourceWindowId,
              let sourceWindow = Window.get(byId: sourceWindowId)
        else { return }
        _ = updatePendingWindowDragIntent(
            sourceWindow: sourceWindow,
            mouseLocation: MousePointerTracker.shared.currentSample.point,
            subject: getCurrentMouseDragSubject(),
            detachOrigin: getCurrentMouseTabDetachOrigin(),
        )
    }
}

@MainActor
func cancelWindowDragActualRectRefresh() {
    windowDragActualRectRefreshTask?.cancel()
    windowDragActualRectRefreshTask = nil
    windowDragActualRectCache = [:]
    lastWindowDragHitTestLogSignature = nil
    lastWindowDragIntentLogSignature = nil
}
