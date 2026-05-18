import Foundation

extension WindowDragIntentDestination {
    func withPreviewZones(_ zones: [WindowDragIntentPreviewZone]) -> WindowDragIntentDestination {
        replacingIntentPreview(
            containerRect: previewContainerRect,
            previewRect: previewRect,
            interactionRect: interactionRect,
            zones: zones
        )
    }

    func replacingIntentPreview(
        containerRect: Rect,
        previewRect: Rect,
        interactionRect: Rect,
        zones: [WindowDragIntentPreviewZone]
    ) -> WindowDragIntentDestination {
        WindowDragIntentDestination(
            kind: kind,
            previewContainerRect: containerRect,
            previewRect: previewRect,
            interactionRect: interactionRect,
            title: title,
            subtitle: subtitle,
            previewStyle: previewStyle,
            previewGeometry: previewGeometry,
            isGroup: isGroup,
            previewZones: zones,
            dropIntentOverlay: dropIntentOverlay,
        )
    }

    func withDropIntentOverlay(_ overlay: WindowDropIntentOverlayModel?) -> WindowDragIntentDestination {
        WindowDragIntentDestination(
            kind: kind,
            previewContainerRect: previewContainerRect,
            previewRect: previewRect,
            interactionRect: interactionRect,
            title: title,
            subtitle: subtitle,
            previewStyle: previewStyle,
            previewGeometry: previewGeometry,
            isGroup: isGroup,
            previewZones: previewZones,
            dropIntentOverlay: overlay,
        )
    }
}
