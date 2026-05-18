import SwiftUI

struct PreviewCornerRadii {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat

    static func uniform(_ radius: CGFloat) -> PreviewCornerRadii {
        PreviewCornerRadii(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
    }
}

struct WindowTabDropOutlineShape: InsettableShape {
    var cornerRadii: PreviewCornerRadii
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(cornerRadii.topLeft, cornerRadii.topRight),
                AnimatablePair(cornerRadii.bottomRight, cornerRadii.bottomLeft)
            )
        }
        set {
            cornerRadii = PreviewCornerRadii(
                topLeft: newValue.first.first,
                topRight: newValue.first.second,
                bottomRight: newValue.second.first,
                bottomLeft: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        WindowTabRoundedPath(cornerRadii: cornerRadii, insetAmount: insetAmount).path(in: rect)
    }

    func inset(by amount: CGFloat) -> WindowTabDropOutlineShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
