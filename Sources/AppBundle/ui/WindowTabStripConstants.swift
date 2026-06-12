import AppKit
import Common
import SwiftUI

// MARK: - Constants

// Initial guess when no window's real corner radius has been measured yet. macOS 27 unified
// the window corner radius system-wide; the true value is measured from live windows at
// runtime (see estimatedWindowPreviewCornerRadius), so this constant only matters until the
// first successful measurement.
let windowTabPreviewCornerRadius: CGFloat = {
    if #available(macOS 26.0, *) { return 26 } else { return 12 }
}()
let windowTabStripContentHorizontalPadding: CGFloat = 3
let windowTabStripGroupHandleWidth: CGFloat = 26
let windowTabStripReservedHandleWidth: CGFloat = 24
let windowTabStripTrailingGroupDragGutterWidth: CGFloat = 28
let windowTabStripCornerRadius: CGFloat = 12
let windowTabStripInnerCornerRadius: CGFloat = 7
let windowTabStripTabSpacing: CGFloat = 4
let windowTabStripPreferredTabWidth: CGFloat = 240
let windowTabStripMinimumTabWidth: CGFloat = 132
let windowTabStripScrollFadeWidth: CGFloat = 22
let windowTabStripScrollOriginTolerance: CGFloat = 0.5
let windowTabStripGroupDragMinimumDistance: CGFloat = 1
let windowTabGroupFrameStrokeWidth: CGFloat = 0.5
let windowTabGroupFrameInnerStrokeWidth: CGFloat = 0.5
// Must be >= the OS standard window corner radius (26pt on macOS 26, unified system-wide on
// macOS 27), otherwise the chrome frame's inner cutout clamps below the real window corners
// and visibly mismatches them. The actual radius comes from per-window measurement; this only
// bounds absurd estimates.
let windowTabGroupFrameMaxInnerCornerRadius: CGFloat = {
    if #available(macOS 26.0, *) { return 36 } else { return 22 }
}()
let windowTabGroupFrameMaxTopInnerCornerRadius: CGFloat = 40
let windowTabGroupCornerShieldOverreach: CGFloat = 7
let windowTabPillAnimation: Animation = .spring(response: 0.28, dampingFraction: 0.72, blendDuration: 0.08)
let windowTabReducedMotionAnimation: Animation = .easeOut(duration: 0.12)

func windowTabStripContentPadding() -> CGFloat {
    windowTabStripContentHorizontalPadding
}

func windowTabStripReservedGroupHandleWidth() -> CGFloat {
    windowTabStripReservedHandleWidth
}

func windowTabStripScrollViewportWidth(stripWidth: CGFloat) -> CGFloat {
    max(
        0,
        stripWidth
            - 16
            - windowTabStripReservedGroupHandleWidth()
            - windowTabStripTrailingGroupDragGutterWidth
            - 18,
    )
}

func windowTabStripTabWidth(stripWidth: CGFloat, count: Int) -> CGFloat {
    let count = max(count, 1)
    let availableWidth = windowTabStripScrollViewportWidth(stripWidth: stripWidth)
        - (windowTabStripContentHorizontalPadding * 2)
        - CGFloat(max(count - 1, 0)) * windowTabStripTabSpacing
    return min(
        max(availableWidth / CGFloat(count), windowTabStripMinimumTabWidth),
        windowTabStripPreferredTabWidth
    )
}

func windowTabStripAvailableTabsWidth(stripWidth: CGFloat) -> CGFloat {
    max(
        0,
        windowTabStripScrollViewportWidth(stripWidth: stripWidth)
            - (windowTabStripContentHorizontalPadding * 2),
    )
}

func windowTabResolvedScrollFadeWidth(stripWidth: CGFloat) -> CGFloat {
    min(windowTabStripScrollFadeWidth, max(stripWidth / 5, 0))
}

func windowTabLeadingScrollFadeWidth(
    isScrollable: Bool,
    contentMinX: CGFloat,
    stripWidth: CGFloat,
) -> CGFloat {
    let firstTabMinX = contentMinX + windowTabStripContentHorizontalPadding
    guard isScrollable, firstTabMinX < -windowTabStripScrollOriginTolerance else { return 0 }
    return windowTabResolvedScrollFadeWidth(stripWidth: stripWidth)
}

func windowTabTrailingScrollFadeWidth(
    isScrollable: Bool,
    contentMaxX: CGFloat,
    viewportWidth: CGFloat,
    stripWidth: CGFloat,
) -> CGFloat {
    let lastTabMaxX = contentMaxX - windowTabStripContentHorizontalPadding
    guard isScrollable, lastTabMaxX > viewportWidth + windowTabStripScrollOriginTolerance else { return 0 }
    return windowTabResolvedScrollFadeWidth(stripWidth: stripWidth)
}

// MARK: - Tab Strip View (manages reorder drag state for all tabs)

let tabReorderVerticalEscapeThreshold: CGFloat = 18
