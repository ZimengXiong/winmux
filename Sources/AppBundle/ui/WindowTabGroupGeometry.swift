import AppKit

@MainActor
private var systemWindowCornerRadiusCache: CGFloat? = nil

/// The system-wide window corner radius (unified on macOS 27), read directly from AppKit by
/// probing a throwaway titled window's frame view. Deterministic — unlike per-window pixel
/// estimation, it can't fluctuate between windows — and tracks future OS changes for free.
@MainActor
func systemWindowCornerRadius() -> CGFloat {
    if let cached = systemWindowCornerRadiusCache { return cached }
    let probe = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.titled],
        backing: .buffered,
        defer: false,
    )
    probe.isReleasedWhenClosed = false
    defer { probe.close() }
    var measured: CGFloat? = nil
    if let frameView = probe.contentView?.superview,
       frameView.responds(to: NSSelectorFromString("cornerRadius")),
       let radius = frameView.value(forKey: "cornerRadius") as? CGFloat,
       radius > 0
    {
        measured = radius
    }
    let resolved = measured ?? windowTabPreviewCornerRadius
    systemWindowCornerRadiusCache = resolved
    return resolved
}

@MainActor
func windowTabGroupAppCornerRadius(activeWindowId: UInt32?) -> CGFloat {
    if #available(macOS 26.0, *) {
        // Unified system radius: stable across windows, no estimation noise.
        return min(max(systemWindowCornerRadius(), 6), windowTabGroupFrameMaxInnerCornerRadius)
    }
    let radius = activeWindowId.map(estimatedWindowPreviewCornerRadius) ?? windowTabPreviewCornerRadius
    return min(max(radius, 6), windowTabGroupFrameMaxInnerCornerRadius)
}

func windowTabGroupOuterCornerRadius(innerCornerRadius _: CGFloat) -> CGFloat {
    windowTabStripCornerRadius
}

func windowTabGroupTopInnerCornerRadius(_ appCornerRadius: CGFloat) -> CGFloat {
    min(
        max(appCornerRadius + windowTabGroupShellHorizontalInset() + 14, windowTabStripCornerRadius + 18),
        windowTabGroupFrameMaxTopInnerCornerRadius
    )
}

func windowTabGroupTopCornerShieldRadius(_ topInnerCornerRadius: CGFloat) -> CGFloat {
    min(topInnerCornerRadius + windowTabGroupCornerShieldOverreach, windowTabGroupFrameMaxTopInnerCornerRadius)
}

func windowTabGroupBottomCornerShieldRadius(_ appCornerRadius: CGFloat) -> CGFloat {
    min(
        appCornerRadius + windowTabGroupCornerShieldOverreach,
        windowTabGroupFrameMaxInnerCornerRadius + windowTabGroupCornerShieldOverreach
    )
}

func windowTabGroupInnerAppFrame(groupSize: CGSize, tabHeight: CGFloat) -> CGRect {
    let horizontalInset = min(windowTabGroupShellHorizontalInset(), groupSize.width / 2)
    let contentTop = min(tabHeight + windowTabGroupShellTopInset(), groupSize.height)
    let availableHeight = max(groupSize.height - contentTop, 0)
    let bottomInset = min(windowTabGroupShellBottomInset(), availableHeight)
    return CGRect(
        x: horizontalInset,
        y: contentTop,
        width: max(groupSize.width - horizontalInset * 2, 0),
        height: max(availableHeight - bottomInset, 0)
    )
}
