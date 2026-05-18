import SwiftUI

struct WindowTabGroupShellShape: Shape {
    let outerRadii: PreviewCornerRadii
    let innerRect: CGRect
    let innerRadii: PreviewCornerRadii

    func path(in rect: CGRect) -> Path {
        var path = WindowTabDropOutlineShape(cornerRadii: outerRadii).path(in: rect)
        if innerRect.width > 0, innerRect.height > 0 {
            path.addPath(WindowTabDropOutlineShape(cornerRadii: innerRadii).path(in: innerRect))
        }
        return path
    }
}
