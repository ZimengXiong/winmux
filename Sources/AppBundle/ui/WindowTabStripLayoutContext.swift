import AppKit

struct WindowTabStripLayoutContext {
    let strip: WindowTabStripViewModel
    let width: CGFloat

    var tabOrder: [UInt32] {
        strip.tabs.map(\.windowId)
    }

    var tabIndicesById: [UInt32: Int] {
        Dictionary(uniqueKeysWithValues: strip.tabs.enumerated().map { ($0.element.windowId, $0.offset) })
    }

    var tabWidth: CGFloat {
        windowTabStripTabWidth(stripWidth: width, count: max(strip.tabs.count, 1))
    }

    var effectiveTabWidth: CGFloat {
        tabWidth + windowTabStripTabSpacing
    }

    var scrollViewportWidth: CGFloat {
        windowTabStripScrollViewportWidth(stripWidth: width)
    }

    var scrollContentWidth: CGFloat {
        CGFloat(strip.tabs.count) * tabWidth
            + CGFloat(max(strip.tabs.count - 1, 0)) * windowTabStripTabSpacing
            + windowTabStripContentHorizontalPadding * 2
    }

    var scrollCoordinateSpaceName: String {
        "window-tab-strip-scroll-\(strip.id.hashValue)"
    }

    var outerTopRadius: CGFloat {
        windowTabGroupOuterCornerRadius(
            innerCornerRadius: windowTabGroupTopInnerCornerRadius(strip.activeWindowCornerRadius)
        )
    }

    func trailingFadeWidth(contentMinX: CGFloat) -> CGFloat {
        windowTabTrailingScrollFadeWidth(
            isScrollable: shouldFadeTabScroll,
            contentMaxX: contentMinX + scrollContentWidth,
            viewportWidth: scrollViewportWidth,
            stripWidth: width,
        )
    }

    func leadingFadeWidth(contentMinX: CGFloat) -> CGFloat {
        windowTabLeadingScrollFadeWidth(
            isScrollable: shouldFadeTabScroll,
            contentMinX: contentMinX,
            stripWidth: width,
        )
    }

    private var shouldFadeTabScroll: Bool {
        scrollContentWidth > scrollViewportWidth + 1
    }
}
