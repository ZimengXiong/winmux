import SwiftUI

struct WindowTabGroupMockTabsView: View {
    let strip: WindowTabStripViewModel
    let stripWidth: CGFloat
    let stripHeight: CGFloat

    var body: some View {
        let tabCount = max(strip.tabs.count, 1)
        let tabWidth = windowTabStripTabWidth(stripWidth: stripWidth, count: tabCount)
        let itemHeight = max(stripHeight - 4, 18)
        let visibleCount = windowTabGroupMockVisibleTabCount(
            stripWidth: stripWidth,
            tabWidth: tabWidth,
            tabCount: tabCount,
        )
        let visibleTabs = Array(strip.tabs.prefix(visibleCount))

        HStack(spacing: 0) {
            Color.clear.frame(width: windowTabStripReservedGroupHandleWidth())
            WindowTabGroupMockTabPillsView(
                strip: strip,
                visibleTabs: visibleTabs,
                tabWidth: tabWidth,
                itemHeight: itemHeight,
            )
            Color.clear.frame(width: windowTabStripReservedGroupHandleWidth())
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(width: stripWidth, height: stripHeight, alignment: .topLeading)
        .allowsHitTesting(false)
        .transaction { $0.animation = nil }
    }
}

func windowTabGroupMockVisibleTabCount(stripWidth: CGFloat, tabWidth: CGFloat, tabCount: Int) -> Int {
    let requestedCount = max(tabCount, 1)
    let availableWidth = windowTabStripAvailableTabsWidth(stripWidth: stripWidth)
    guard availableWidth > 0 else { return 1 }
    let effectiveTabWidth = max(tabWidth + windowTabStripTabSpacing, 1)
    let fittingCount = Int(ceil((availableWidth + windowTabStripTabSpacing) / effectiveTabWidth))
    return max(1, min(requestedCount, fittingCount))
}
