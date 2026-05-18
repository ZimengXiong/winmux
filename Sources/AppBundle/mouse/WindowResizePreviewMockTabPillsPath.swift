import AppKit

let windowResizePreviewMockTabSpacing: CGFloat = 8

func windowResizePreviewMockTabPillsPath(in bounds: CGRect, headerHeight: CGFloat, tabCount: Int) -> CGPath {
    let path = CGMutablePath()
    guard bounds.width > 0, bounds.height > 0 else { return path }

    let resolvedHeaderHeight = min(max(headerHeight, 18), bounds.height)
    let horizontalInset = min(windowTabGroupShellHorizontalInset(), bounds.width / 2)
    let handleWidth = windowTabStripReservedGroupHandleWidth()
    let contentPadding = windowTabStripContentPadding()
    let minX = bounds.minX + horizontalInset + handleWidth + contentPadding
    let maxX = bounds.maxX - horizontalInset - handleWidth - contentPadding
    let availableWidth = max(maxX - minX, 0)
    guard availableWidth > 0 else { return path }

    let desiredTabWidth = windowTabStripTabWidth(stripWidth: bounds.width, count: max(tabCount, 1))
    let visibleCount = windowResizePreviewMockTabVisibleCount(
        availableWidth: availableWidth,
        tabCount: tabCount,
        tabWidth: desiredTabWidth,
    )
    let tabWidth = min(desiredTabWidth, availableWidth)
    let tabHeight = max(resolvedHeaderHeight - 8, 10)
    let tabY = bounds.minY + (resolvedHeaderHeight - tabHeight) / 2
    var tabX = minX

    for _ in 0..<visibleCount {
        let remainingWidth = maxX - tabX
        guard remainingWidth >= 24 else { break }
        let rect = CGRect(
            x: tabX,
            y: tabY,
            width: min(tabWidth, remainingWidth),
            height: tabHeight,
        )
        let radius = min(12, rect.height / 2)
        path.addPath(windowResizePreviewRoundedRectPath(in: rect, radii: .uniform(radius)))
        tabX += tabWidth + windowResizePreviewMockTabSpacing
    }

    return path
}

func windowResizePreviewMockTabVisibleCount(
    availableWidth: CGFloat,
    tabCount: Int,
    tabWidth: CGFloat,
) -> Int {
    let requestedCount = max(tabCount, 1)
    let effectiveWidth = max(tabWidth + windowResizePreviewMockTabSpacing, 1)
    let fittingCount = Int(ceil((availableWidth + windowResizePreviewMockTabSpacing) / effectiveWidth))
    return max(1, min(requestedCount, fittingCount))
}
