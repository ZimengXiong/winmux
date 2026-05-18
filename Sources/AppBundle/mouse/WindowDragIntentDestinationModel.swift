struct WindowDragIntentDestination {
    let kind: WindowDragIntentKind
    let previewContainerRect: Rect
    let previewRect: Rect
    let interactionRect: Rect
    let title: String
    let subtitle: String
    let previewStyle: WindowTabDropPreviewStyle
    let previewGeometry: WindowTabDropPreviewGeometry
    let isGroup: Bool
    let previewZones: [WindowDragIntentPreviewZone]
    let dropIntentOverlay: WindowDropIntentOverlayModel?

    init(
        kind: WindowDragIntentKind,
        previewContainerRect: Rect,
        previewRect: Rect,
        interactionRect: Rect,
        title: String,
        subtitle: String,
        previewStyle: WindowTabDropPreviewStyle,
        previewGeometry: WindowTabDropPreviewGeometry,
        isGroup: Bool,
        previewZones: [WindowDragIntentPreviewZone] = [],
        dropIntentOverlay: WindowDropIntentOverlayModel? = nil,
    ) {
        self.kind = kind
        self.previewContainerRect = previewContainerRect
        self.previewRect = previewRect
        self.interactionRect = interactionRect
        self.title = title
        self.subtitle = subtitle
        self.previewStyle = previewStyle
        self.previewGeometry = previewGeometry
        self.isGroup = isGroup
        self.previewZones = previewZones
        self.dropIntentOverlay = dropIntentOverlay
    }
}
