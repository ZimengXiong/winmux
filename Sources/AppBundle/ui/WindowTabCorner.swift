import SwiftUI

enum WindowTabCorner {
    case topRight
    case bottomRight
    case bottomLeft
    case topLeft

    func arc(in rect: CGRect, radius: CGFloat) -> (center: CGPoint, start: Angle, end: Angle) {
        switch self {
            case .topRight:
                return (
                    CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                    .degrees(-90),
                    .degrees(0)
                )
            case .bottomRight:
                return (
                    CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                    .degrees(0),
                    .degrees(90)
                )
            case .bottomLeft:
                return (
                    CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                    .degrees(90),
                    .degrees(180)
                )
            case .topLeft:
                return (
                    CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                    .degrees(180),
                    .degrees(270)
                )
        }
    }
}
