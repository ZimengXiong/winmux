import SwiftUI

struct WindowTabRoundedPath {
    var cornerRadii: PreviewCornerRadii
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return Path() }
        let radii = clampedRadii(in: rect)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radii.topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radii.topRight, y: rect.minY))
        addArcIfNeeded(to: &path, rect: rect, radius: radii.topRight, corner: .topRight)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radii.bottomRight))
        addArcIfNeeded(to: &path, rect: rect, radius: radii.bottomRight, corner: .bottomRight)
        path.addLine(to: CGPoint(x: rect.minX + radii.bottomLeft, y: rect.maxY))
        addArcIfNeeded(to: &path, rect: rect, radius: radii.bottomLeft, corner: .bottomLeft)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radii.topLeft))
        addArcIfNeeded(to: &path, rect: rect, radius: radii.topLeft, corner: .topLeft)
        path.closeSubpath()
        return path
    }

    private func clampedRadii(in rect: CGRect) -> PreviewCornerRadii {
        let maxRadius = min(rect.width, rect.height) / 2
        return PreviewCornerRadii(
            topLeft: min(cornerRadii.topLeft, maxRadius),
            topRight: min(cornerRadii.topRight, maxRadius),
            bottomRight: min(cornerRadii.bottomRight, maxRadius),
            bottomLeft: min(cornerRadii.bottomLeft, maxRadius)
        )
    }

    private func addArcIfNeeded(to path: inout Path, rect: CGRect, radius: CGFloat, corner: WindowTabCorner) {
        guard radius > 0 else { return }
        let arc = corner.arc(in: rect, radius: radius)
        path.addArc(center: arc.center, radius: radius, startAngle: arc.start, endAngle: arc.end, clockwise: false)
    }
}
