import SwiftUI

struct WindowTabGroupFrameMetrics {
    let tabHeight: CGFloat
    let innerFrame: CGRect
    let appCornerRadius: CGFloat
    let topInnerCornerRadius: CGFloat
    let outerRadii: PreviewCornerRadii
    let innerRadii: PreviewCornerRadii

    init(strip: WindowTabStripViewModel, groupSize: CGSize) {
        tabHeight = min(strip.frame.height, groupSize.height)
        innerFrame = windowTabGroupInnerAppFrame(groupSize: groupSize, tabHeight: tabHeight)
        appCornerRadius = strip.activeWindowCornerRadius
        topInnerCornerRadius = windowTabGroupTopInnerCornerRadius(appCornerRadius)
        let outerTopRadius = windowTabGroupOuterCornerRadius(innerCornerRadius: topInnerCornerRadius)
        let bottomOuterRadius = appCornerRadius + windowTabGroupShellHorizontalInset()
        outerRadii = PreviewCornerRadii(
            topLeft: outerTopRadius,
            topRight: outerTopRadius,
            bottomRight: bottomOuterRadius,
            bottomLeft: bottomOuterRadius
        )
        innerRadii = PreviewCornerRadii(
            topLeft: topInnerCornerRadius,
            topRight: topInnerCornerRadius,
            bottomRight: appCornerRadius,
            bottomLeft: appCornerRadius
        )
    }

    var outerShape: WindowTabDropOutlineShape {
        WindowTabDropOutlineShape(cornerRadii: outerRadii)
    }
}
