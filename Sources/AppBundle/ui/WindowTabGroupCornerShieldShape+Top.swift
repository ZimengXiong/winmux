import SwiftUI

extension WindowTabGroupCornerShieldShape {
    func addTopLeftShield(to path: inout Path, radius: CGFloat) {
        let rect = CGRect(x: innerRect.minX, y: innerRect.minY, width: radius, height: radius)
        let center = CGPoint(x: innerRect.minX + radius, y: innerRect.minY + radius)
        path.addRect(rect)
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: innerRect.minY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(180),
            clockwise: true,
        )
        path.closeSubpath()
    }

    func addTopRightShield(to path: inout Path, radius: CGFloat) {
        let rect = CGRect(x: innerRect.maxX - radius, y: innerRect.minY, width: radius, height: radius)
        let center = CGPoint(x: innerRect.maxX - radius, y: innerRect.minY + radius)
        path.addRect(rect)
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: innerRect.minY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false,
        )
        path.closeSubpath()
    }
}
