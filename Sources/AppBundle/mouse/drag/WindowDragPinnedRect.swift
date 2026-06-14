import Common

@MainActor
func pinnedDraggedWindowRect(for sourceWindow: Window, subject: WindowDragSubject, fallbackAnchorRect: Rect) -> Rect {
    switch subject {
        case .window:
            return fallbackAnchorRect
        case .group:
            return resolvedDraggedWindowAnchorRect(for: sourceWindow, subject: .window) ?? fallbackAnchorRect
    }
}
