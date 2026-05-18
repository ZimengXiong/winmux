import AppKit
import Common

func windowResizePreviewTabGroupShellPath(in bounds: CGRect, headerHeight: CGFloat) -> CGPath {
    let path = CGMutablePath()
    guard bounds.width > 0, bounds.height > 0 else { return path }

    let shellInset = min(windowTabGroupShellHorizontalInset(), bounds.width / 2)
    let bottomInset = min(windowTabGroupShellBottomInset(), bounds.height)
    let tabHeight = min(max(headerHeight, 0), bounds.height)
    let contentHeight = max(bounds.height - tabHeight - bottomInset, 0)
    let innerRect = CGRect(
        x: bounds.minX + shellInset,
        y: bounds.minY + tabHeight,
        width: max(bounds.width - shellInset * 2, 0),
        height: contentHeight,
    )
    let appRadius = min(max(min(innerRect.width, innerRect.height) * 0.04, 8), 22)
    let topInnerRadius = min(max(appRadius + shellInset + 14, 30), 40)
    let bottomOuterRadius = appRadius + shellInset

    path.addPath(windowResizePreviewRoundedRectPath(
        in: bounds,
        radii: ResizePreviewCornerRadii(
            topLeft: 12,
            topRight: 12,
            bottomRight: bottomOuterRadius,
            bottomLeft: bottomOuterRadius,
        )
    ))
    if innerRect.width > 0, innerRect.height > 0 {
        path.addPath(windowResizePreviewRoundedRectPath(
            in: innerRect,
            radii: ResizePreviewCornerRadii(
                topLeft: topInnerRadius,
                topRight: topInnerRadius,
                bottomRight: appRadius,
                bottomLeft: appRadius,
            )
        ))
    }
    return path
}
