import CoreGraphics

struct WindowDropIntentResolution {
    let intent: WindowDropIntent
    let targetFrame: Rect
    let targetCornerRadius: CGFloat?
    let zones: [WindowIntentZone]
}

struct WindowDropIntentResolver {
    func resolve(
        sourceWindowId: UInt32,
        targetWindowId: UInt32,
        pointer: CGPoint,
        targetFrame: Rect,
        targetCornerRadius: CGFloat? = nil,
    ) -> WindowDropIntentResolution? {
        guard sourceWindowId != targetWindowId,
              targetFrame.contains(pointer),
              let zone = WindowIntentZoneBuilder.zone(at: pointer, in: targetFrame)
        else {
            return nil
        }
        return WindowDropIntentResolution(
            intent: WindowDropIntent(
                sourceWindowId: sourceWindowId,
                targetWindowId: targetWindowId,
                zone: zone,
            ),
            targetFrame: targetFrame,
            targetCornerRadius: targetCornerRadius,
            zones: WindowIntentZoneBuilder.zones(in: targetFrame),
        )
    }
}
