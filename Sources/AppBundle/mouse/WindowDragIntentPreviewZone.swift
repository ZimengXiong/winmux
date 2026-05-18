struct WindowDragIntentPreviewZone {
    let rect: Rect
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let isActive: Bool

    var viewModel: WindowTabDropPreviewZoneViewModel {
        WindowTabDropPreviewZoneViewModel(
            frame: rect.toAppKitScreenRect,
            style: style,
            geometry: geometry,
            isActive: isActive,
        )
    }
}
