import CoreGraphics

struct WindowIntentZone: Identifiable {
    var id: WindowDropZone { zone }
    let zone: WindowDropZone
    let frame: Rect
}

enum WindowIntentZoneBuilder {
    static func zones(in frame: Rect) -> [WindowIntentZone] {
        guard frame.width > 0, frame.height > 0 else { return [] }

        let tabHeight = min(max(frame.height * 0.18, 32), frame.height / 3)
        let body = Rect(
            topLeftX: frame.minX,
            topLeftY: frame.minY + tabHeight,
            width: frame.width,
            height: max(frame.height - tabHeight, 0),
        )
        guard body.width > 0, body.height > 0 else {
            return [WindowIntentZone(zone: .tab, frame: frame)]
        }

        let columnWidth = body.width / 3
        let rowHeight = body.height / 3
        return [
            WindowIntentZone(zone: .tab, frame: Rect(topLeftX: frame.minX, topLeftY: frame.minY, width: frame.width, height: tabHeight)),
            WindowIntentZone(zone: .left, frame: Rect(topLeftX: body.minX, topLeftY: body.minY, width: columnWidth, height: body.height)),
            WindowIntentZone(zone: .right, frame: Rect(topLeftX: body.maxX - columnWidth, topLeftY: body.minY, width: columnWidth, height: body.height)),
            WindowIntentZone(zone: .top, frame: Rect(topLeftX: body.minX + columnWidth, topLeftY: body.minY, width: columnWidth, height: rowHeight)),
            WindowIntentZone(zone: .middle, frame: Rect(topLeftX: body.minX + columnWidth, topLeftY: body.minY + rowHeight, width: columnWidth, height: rowHeight)),
            WindowIntentZone(zone: .bottom, frame: Rect(topLeftX: body.minX + columnWidth, topLeftY: body.maxY - rowHeight, width: columnWidth, height: rowHeight)),
        ].filter { $0.frame.width > 0 && $0.frame.height > 0 }
    }

    static func zone(at point: CGPoint, in frame: Rect) -> WindowDropZone? {
        guard frame.contains(point) else { return nil }
        return zones(in: frame).reversed().first { $0.frame.contains(point) }?.zone
    }
}
