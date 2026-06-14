import AppKit
import Common

extension Rect {
    func clampedPoint(_ point: CGPoint) -> CGPoint {
        let epsilon = CGFloat(0.001)
        return CGPoint(
            x: min(max(point.x, minX + epsilon), maxX - epsilon),
            y: min(max(point.y, minY + epsilon), maxY - epsilon),
        )
    }

    func isEqual(to other: Rect) -> Bool {
        topLeftX == other.topLeftX && topLeftY == other.topLeftY && width == other.width && height == other.height
    }

    var area: CGFloat {
        width * height
    }

    func intersection(_ other: Rect) -> Rect {
        let minX = max(self.minX, other.minX)
        let minY = max(self.minY, other.minY)
        let maxX = min(self.maxX, other.maxX)
        let maxY = min(self.maxY, other.maxY)
        return Rect(
            topLeftX: minX,
            topLeftY: minY,
            width: max(maxX - minX, 0),
            height: max(maxY - minY, 0),
        )
    }

    func isApproximatelyEqual(to other: Rect, tolerance: CGFloat) -> Bool {
        abs(topLeftX - other.topLeftX) <= tolerance &&
            abs(topLeftY - other.topLeftY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }
}
