struct PendingWindowDragIntent {
    let sourceWindowId: UInt32
    let sourceSubject: WindowDragSubject
    let kind: WindowDragIntentKind
    let previewRect: Rect
    let interactionRect: Rect
    let title: String
    let subtitle: String
    let previewStyle: WindowTabDropPreviewStyle
    let previewGeometry: WindowTabDropPreviewGeometry
    let isGroup: Bool
    let isPointerSettled: Bool
}

@MainActor
func debugPendingWindowDragIntentSummary() -> (kind: WindowDragIntentKind, previewRect: Rect, interactionRect: Rect)? {
    guard let pendingWindowDragIntent else { return nil }
    return (
        kind: pendingWindowDragIntent.kind,
        previewRect: pendingWindowDragIntent.previewRect,
        interactionRect: pendingWindowDragIntent.interactionRect,
    )
}
