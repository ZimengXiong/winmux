import CoreGraphics

struct WindowDropIntentResolution {
    let intent: WindowDropIntent
    let targetFrame: Rect
    let zones: [WindowIntentZone]
}

struct WindowDropIntentResolver {
    func resolve(
        sourceWindowId: UInt32,
        targetWindowId: UInt32,
        pointer: CGPoint,
        targetFrame: Rect,
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
            zones: WindowIntentZoneBuilder.zones(in: targetFrame),
        )
    }
}
