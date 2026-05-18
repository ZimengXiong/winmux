import SwiftUI

struct WindowTabGroupCornerShieldShape: Shape {
    let innerRect: CGRect
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    func path(in _: CGRect) -> Path {
        var path = Path()
        guard innerRect.width > 0, innerRect.height > 0 else { return path }
        let maxRadius = min(innerRect.width / 2, innerRect.height / 2)
        let resolvedTopRadius = min(topRadius, maxRadius)
        let resolvedBottomRadius = min(bottomRadius, maxRadius)
        if resolvedTopRadius > 0 {
            addTopLeftShield(to: &path, radius: resolvedTopRadius)
            addTopRightShield(to: &path, radius: resolvedTopRadius)
        }
        if resolvedBottomRadius > 0 {
            addBottomLeftShield(to: &path, radius: resolvedBottomRadius)
            addBottomRightShield(to: &path, radius: resolvedBottomRadius)
        }
        return path
    }
}
