@MainActor
func cacheCurrentActualRects(_ windows: [Window]) {
    windowDragActualRectCache = windows.reduce(into: [:]) { result, window in
        if let rect = window.lastKnownActualRect {
            result[window.windowId] = rect
        }
    }
}

@MainActor
func refreshActualRects(_ windows: [Window], sourceWindowId: UInt32) async {
    for window in windows {
        let previousRect = window.lastKnownActualRect
        let refreshedRect = try? await window.getAxRect()
        if let refreshedRect {
            windowDragActualRectCache[window.windowId] = resolveWindowDragActualRect(
                cached: windowDragActualRectCache[window.windowId],
                candidate: refreshedRect,
                layout: window.lastAppliedLayoutPhysicalRect,
            )
        }
        if let refreshedRect, !(previousRect.map { $0.isEqual(to: refreshedRect) } ?? false) {
            debugFocusLog(
                "windowDragActualRect.refresh source=\(sourceWindowId) target=\(window.windowId) old=\(debugDescribe(previousRect)) new=\(debugDescribe(refreshedRect)) layout=\(debugDescribe(window.lastAppliedLayoutPhysicalRect))"
            )
        }
    }
}
