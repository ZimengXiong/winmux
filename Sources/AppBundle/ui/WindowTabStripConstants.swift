import AppKit
import Common
import SwiftUI

// MARK: - Constants

let windowTabPreviewCornerRadius: CGFloat = 12
let windowTabStripContentHorizontalPadding: CGFloat = 2
let windowTabStripGroupHandleWidth: CGFloat = 2
let windowTabStripCornerRadius: CGFloat = 12
let windowTabStripInnerCornerRadius: CGFloat = 12
let windowTabStripTabSpacing: CGFloat = 8
let windowTabStripPreferredTabWidth: CGFloat = 240
let windowTabStripMinimumTabWidth: CGFloat = 132
let windowTabStripScrollFadeWidth: CGFloat = 22
let windowTabStripScrollOriginTolerance: CGFloat = 1
let windowTabGroupFrameStrokeWidth: CGFloat = 0.5
let windowTabGroupFrameInnerStrokeWidth: CGFloat = 0.5
let windowTabGroupFrameMaxInnerCornerRadius: CGFloat = 22
let windowTabGroupFrameMaxTopInnerCornerRadius: CGFloat = 40
let windowTabGroupCornerShieldOverreach: CGFloat = 7
let windowTabPillAnimation: Animation = .spring(response: 0.28, dampingFraction: 0.72, blendDuration: 0.08)
let windowTabReducedMotionAnimation: Animation = .easeOut(duration: 0.12)

func windowTabStripContentPadding() -> CGFloat {
    windowTabStripContentHorizontalPadding
}

func windowTabStripReservedGroupHandleWidth() -> CGFloat {
    windowTabStripGroupHandleWidth
}

func windowTabStripAvailableTabsWidth(stripWidth: CGFloat) -> CGFloat {
    max(
        0,
        stripWidth
            - (windowTabStripReservedGroupHandleWidth() * 2)
            - (windowTabStripContentHorizontalPadding * 2),
    )
}

func windowTabStripTabWidth(stripWidth: CGFloat, count: Int) -> CGFloat {
    let availableWidth = windowTabStripAvailableTabsWidth(stripWidth: stripWidth)
    guard availableWidth > 0 else { return windowTabStripPreferredTabWidth }
    return max(windowTabStripMinimumTabWidth, min(windowTabStripPreferredTabWidth, availableWidth))
}

func windowTabResolvedScrollFadeWidth(stripWidth: CGFloat) -> CGFloat {
    min(windowTabStripScrollFadeWidth, max(stripWidth / 5, 0))
}

func windowTabLeadingScrollFadeWidth(isScrollable: Bool, contentMinX: CGFloat, stripWidth: CGFloat) -> CGFloat {
    guard isScrollable, contentMinX < -windowTabStripScrollOriginTolerance else { return 0 }
    return windowTabResolvedScrollFadeWidth(stripWidth: stripWidth)
}

func windowTabTrailingScrollFadeWidth(isScrollable: Bool, stripWidth: CGFloat) -> CGFloat {
    isScrollable ? windowTabResolvedScrollFadeWidth(stripWidth: stripWidth) : 0
}

// MARK: - Tab Strip View (manages reorder drag state for all tabs)

let tabReorderVerticalEscapeThreshold: CGFloat = 18

