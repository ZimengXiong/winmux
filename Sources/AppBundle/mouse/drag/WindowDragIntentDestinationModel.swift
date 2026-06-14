struct WindowDragIntentDestination {
    var kind: WindowDragIntentKind
    var previewRect: Rect
    var interactionRect: Rect
    var title: String
    var subtitle: String
    var previewStyle: WindowTabDropPreviewStyle
    var previewGeometry: WindowTabDropPreviewGeometry
    var isGroup: Bool
    var dropIntentOverlay: WindowDropIntentOverlayModel?

    init(
        kind: WindowDragIntentKind,
        previewRect: Rect,
        interactionRect: Rect,
        title: String,
        subtitle: String,
        previewStyle: WindowTabDropPreviewStyle,
        previewGeometry: WindowTabDropPreviewGeometry,
        isGroup: Bool,
        dropIntentOverlay: WindowDropIntentOverlayModel? = nil,
    ) {
        self.kind = kind
        self.previewRect = previewRect
        self.interactionRect = interactionRect
        self.title = title
        self.subtitle = subtitle
        self.previewStyle = previewStyle
        self.previewGeometry = previewGeometry
        self.isGroup = isGroup
        self.dropIntentOverlay = dropIntentOverlay
    }
}
