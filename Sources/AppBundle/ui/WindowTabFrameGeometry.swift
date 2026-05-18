import AppKit
import Common

@MainActor
func windowTabGroupFrameRect(forActiveWindowContentRect contentRect: Rect) -> Rect {
    let horizontalInset = windowTabGroupShellHorizontalInset()
    let topInset = resolvedWindowTabBarHeight() + windowTabGroupShellTopInset()
    let bottomInset = windowTabGroupShellBottomInset()
    return Rect(
        topLeftX: contentRect.topLeftX - horizontalInset,
        topLeftY: contentRect.topLeftY - topInset,
        width: max(contentRect.width + horizontalInset * 2, 0),
        height: max(contentRect.height + topInset + bottomInset, 0),
    )
}

@MainActor
func windowTabBarRect(forGroupFrameRect groupFrameRect: Rect) -> Rect {
    Rect(
        topLeftX: groupFrameRect.topLeftX,
        topLeftY: groupFrameRect.topLeftY,
        width: groupFrameRect.width,
        height: min(resolvedWindowTabBarHeight(), groupFrameRect.height),
    )
}

extension Rect {
    var toAppKitScreenRect: CGRect {
        CGRect(
            x: minX,
            y: mainMonitor.height - topLeftY - height,
            width: width,
            height: height,
        )
    }
}
