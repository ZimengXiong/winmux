import SwiftUI

struct WindowTabGroupShellShape: Shape {
    var tabBarHeight: CGFloat
    var activeWindowCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: windowTabStripCornerRadius, height: windowTabStripCornerRadius),
            style: .continuous,
        )
        let innerRect = Self.innerRect(in: rect, tabBarHeight: tabBarHeight)
        if innerRect.width > 0, innerRect.height > 0 {
            path.addPath(WindowTabGroupInnerBoundaryShape(
                tabBarHeight: tabBarHeight,
                activeWindowCornerRadius: activeWindowCornerRadius
            ).path(in: rect))
        }
        return path
    }

    static func innerRect(in rect: CGRect, tabBarHeight: CGFloat) -> CGRect {
        let horizontalInset = min(windowTabGroupShellHorizontalInset(), rect.width / 2)
        let contentTop = min(tabBarHeight + windowTabGroupShellTopInset(), rect.height)
        let availableHeight = max(rect.height - contentTop, 0)
        let bottomInset = min(windowTabGroupShellBottomInset(), availableHeight)
        return CGRect(
            x: rect.minX + horizontalInset,
            y: rect.minY + contentTop,
            width: max(rect.width - horizontalInset * 2, 0),
            height: max(availableHeight - bottomInset, 0),
        )
    }
}

struct WindowTabGroupInnerBoundaryShape: Shape {
    var tabBarHeight: CGFloat
    var activeWindowCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let innerRect = WindowTabGroupShellShape.innerRect(in: rect, tabBarHeight: tabBarHeight)
        guard innerRect.width > 0, innerRect.height > 0 else { return Path() }

        let maxRadius = min(innerRect.width / 2, innerRect.height / 2)
        let topRadius = min(windowTabGroupTopInnerCornerRadius(activeWindowCornerRadius), maxRadius)
        let bottomRadius = min(activeWindowCornerRadius, maxRadius)

        return Path { path in
            path.move(to: CGPoint(x: innerRect.minX + topRadius, y: innerRect.minY))
            path.addLine(to: CGPoint(x: innerRect.maxX - topRadius, y: innerRect.minY))
            path.addQuadCurve(
                to: CGPoint(x: innerRect.maxX, y: innerRect.minY + topRadius),
                control: CGPoint(x: innerRect.maxX, y: innerRect.minY),
            )
            path.addLine(to: CGPoint(x: innerRect.maxX, y: innerRect.maxY - bottomRadius))
            path.addQuadCurve(
                to: CGPoint(x: innerRect.maxX - bottomRadius, y: innerRect.maxY),
                control: CGPoint(x: innerRect.maxX, y: innerRect.maxY),
            )
            path.addLine(to: CGPoint(x: innerRect.minX + bottomRadius, y: innerRect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: innerRect.minX, y: innerRect.maxY - bottomRadius),
                control: CGPoint(x: innerRect.minX, y: innerRect.maxY),
            )
            path.addLine(to: CGPoint(x: innerRect.minX, y: innerRect.minY + topRadius))
            path.addQuadCurve(
                to: CGPoint(x: innerRect.minX + topRadius, y: innerRect.minY),
                control: CGPoint(x: innerRect.minX, y: innerRect.minY),
            )
            path.closeSubpath()
        }
    }
}
