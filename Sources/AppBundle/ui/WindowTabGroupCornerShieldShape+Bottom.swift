import SwiftUI

extension WindowTabGroupCornerShieldShape {
    func addBottomLeftShield(to path: inout Path, radius: CGFloat) {
        let rect = CGRect(x: innerRect.minX, y: innerRect.maxY - radius, width: radius, height: radius)
        let center = CGPoint(x: innerRect.minX + radius, y: innerRect.maxY - radius)
        path.addRect(rect)
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: innerRect.maxY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false,
        )
        path.closeSubpath()
    }

    func addBottomRightShield(to path: inout Path, radius: CGFloat) {
        let rect = CGRect(x: innerRect.maxX - radius, y: innerRect.maxY - radius, width: radius, height: radius)
        let center = CGPoint(x: innerRect.maxX - radius, y: innerRect.maxY - radius)
        path.addRect(rect)
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: innerRect.maxY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true,
        )
        path.closeSubpath()
    }
}
