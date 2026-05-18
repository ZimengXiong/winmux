import AppKit
import SwiftUI

extension WindowTabStripView {
    func tabStripBody(stripWidth: CGFloat, stripHeight: CGFloat) -> some View {
        let context = WindowTabStripLayoutContext(strip: strip, width: stripWidth)
        let itemHeight = max(stripHeight - 4, 18)
        let activeWindowId = strip.tabs.first(where: \.isActive)?.windowId
        let groupDragWindowId = activeWindowId ?? strip.tabs.first?.windowId
        let shape = windowTabStripShape(outerTopRadius: context.outerTopRadius)

        return HStack(spacing: 0) {
            WindowTabGroupHandleView(
                windowId: groupDragWindowId,
                workspaceName: strip.workspaceName
            )

            tabScrollView(context: context, itemHeight: itemHeight)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(groupDragGesture(for: groupDragWindowId))

            WindowTabGroupHandleView(
                windowId: groupDragWindowId,
                workspaceName: strip.workspaceName
            )
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(width: stripWidth, height: stripHeight)
        .background {
            if drawsChrome {
                shape.fill(mattePanelFill)
                shape.strokeBorder(mattePanelBorder, lineWidth: windowTabGroupFrameStrokeWidth)
            }
        }
        .clipShape(shape)
        .animation(reduceMotion ? windowTabReducedMotionAnimation : windowTabPillAnimation, value: hoveredTabId)
        .animation(reduceMotion ? windowTabReducedMotionAnimation : windowTabPillAnimation, value: activeWindowId)
        .onChange(of: context.tabOrder) { newOrder in
            clearPendingReorderDropIfModelApplied(currentOrder: newOrder)
        }
    }

    func tabScrollView(context: WindowTabStripLayoutContext, itemHeight: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: windowTabStripTabSpacing) {
                ForEach(strip.tabs) { tab in
                    tabItem(tab, context: context, itemHeight: itemHeight)
                }
            }
            .padding(.horizontal, windowTabStripContentHorizontalPadding)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WindowTabStripScrollContentMinXPreferenceKey.self,
                        value: proxy.frame(in: .named(context.scrollCoordinateSpaceName)).minX,
                    )
                }
            }
        }
        .coordinateSpace(name: context.scrollCoordinateSpaceName)
        .onPreferenceChange(WindowTabStripScrollContentMinXPreferenceKey.self) { nextMinX in
            guard abs(tabScrollContentMinX - nextMinX) > 0.5 else { return }
            tabScrollContentMinX = nextMinX
        }
        .mask {
            WindowTabStripScrollFadeMask(
                leadingFadeWidth: context.leadingFadeWidth(contentMinX: tabScrollContentMinX),
                trailingFadeWidth: context.trailingFadeWidth,
            )
        }
    }

}
