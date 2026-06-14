func resolveWindowDragActualRect(cached: Rect?, candidate: Rect, layout: Rect?) -> Rect {
    guard let cached, let layout else { return candidate }
    guard candidate.isApproximatelyEqual(to: layout, tolerance: 1) else { return candidate }
    guard cached.area > candidate.area + 1 else { return candidate }
    guard cached.intersection(candidate).area >= candidate.area * 0.85 else { return candidate }
    return cached
}

@MainActor
func currentWindowDragActualRect(_ window: Window) -> Rect? {
    guard let current = window.lastKnownActualRect else { return windowDragActualRectCache[window.windowId] }
    return resolveWindowDragActualRect(
        cached: windowDragActualRectCache[window.windowId],
        candidate: current,
        layout: window.lastAppliedLayoutPhysicalRect,
    )
}
