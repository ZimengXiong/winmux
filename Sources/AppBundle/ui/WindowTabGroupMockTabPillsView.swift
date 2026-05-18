import SwiftUI

struct WindowTabGroupMockTabPillsView: View {
    let strip: WindowTabStripViewModel
    let visibleTabs: [WindowTabItemViewModel]
    let tabWidth: CGFloat
    let itemHeight: CGFloat

    var body: some View {
        HStack(spacing: windowTabStripTabSpacing) {
            if visibleTabs.isEmpty {
                WindowTabMockPillView(isActive: true)
                    .frame(width: tabWidth, height: itemHeight)
            } else {
                ForEach(Array(visibleTabs.enumerated()), id: \.element.windowId) { index, tab in
                    WindowTabMockPillView(isActive: tab.isActive || (strip.activeWindowId == nil && index == 0))
                        .frame(width: tabWidth, height: itemHeight)
                }
            }
        }
        .padding(.horizontal, windowTabStripContentHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

struct WindowTabMockPillView: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.14 : 0.07))
                .padding(.vertical, 2)

            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(isActive ? 0.12 : 0.07), lineWidth: 0.5)
                .padding(.vertical, 2)
        }
    }
}
