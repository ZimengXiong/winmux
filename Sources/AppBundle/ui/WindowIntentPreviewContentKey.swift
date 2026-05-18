import CoreGraphics

struct WindowIntentPreviewContentKey: Equatable {
    let containerSize: CGSize
    let referenceWindowId: UInt32?
    let frame: CGRect
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let zones: [WindowTabDropPreviewZoneViewModel]

    init(model: WindowTabDropPreviewViewModel) {
        containerSize = model.containerFrame.size
        referenceWindowId = model.referenceWindowId
        frame = model.frame
        style = model.style
        geometry = model.geometry
        zones = model.zones
    }
}
