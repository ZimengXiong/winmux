import AppKit
import SwiftUI

extension WindowTabStripView {
    func tabStripBody(stripWidth: CGFloat, stripHeight: CGFloat) -> some View {
        let context = WindowTabStripLayoutContext(strip: strip, width: stripWidth)
        let itemHeight = min(max(stripHeight - 10, 18), 26)
        let activeWindowId = strip.tabs.first(where: \.isActive)?.windowId
        let groupDragWindowId = activeWindowId ?? strip.tabs.first?.windowId

        return HStack(spacing: 6) {
            WindowTabGroupHandleView(
                windowId: groupDragWindowId,
                workspaceName: strip.workspaceName
            )

            tabScrollView(
                context: context,
                itemHeight: itemHeight,
                groupDragWindowId: groupDragWindowId,
            )
                .frame(maxWidth: .infinity)

            Color.clear
                .frame(width: windowTabStripTrailingGroupDragGutterWidth)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard let groupDragWindowId, !isWindowTabStripDragInProgress() else { return }
                    focusWindowFromTabStripClick(groupDragWindowId, fallbackWorkspace: strip.workspaceName)
                }
                .gesture(groupDragGesture(for: groupDragWindowId))

            WindowTabGroupHandleView(
                windowId: groupDragWindowId,
                workspaceName: strip.workspaceName
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(width: stripWidth, height: stripHeight)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: windowTabStripCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: windowTabStripCornerRadius,
            style: .continuous,
        ))
        .animation(reduceMotion ? windowTabReducedMotionAnimation : windowTabPillAnimation, value: hoveredTabId)
        .animation(reduceMotion ? windowTabReducedMotionAnimation : windowTabPillAnimation, value: activeWindowId)
        .onChange(of: context.tabOrder) { newOrder in
            clearPendingReorderDropIfModelApplied(currentOrder: newOrder)
        }
    }

    func tabScrollView(
        context: WindowTabStripLayoutContext,
        itemHeight: CGFloat,
        groupDragWindowId: UInt32?,
    ) -> some View {
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
                        key: WindowTabStripScrollContentFramePreferenceKey.self,
                        value: proxy.frame(in: .named(context.scrollCoordinateSpaceName)),
                    )
                }
            }
        }
        .coordinateSpace(name: context.scrollCoordinateSpaceName)
        .onPreferenceChange(WindowTabStripScrollContentFramePreferenceKey.self) { nextFrame in
            if abs(tabScrollContentMinX - nextFrame.minX) > 0.5 {
                tabScrollContentMinX = nextFrame.minX
            }
            if abs(tabScrollContentMaxX - nextFrame.maxX) > 0.5 {
                tabScrollContentMaxX = nextFrame.maxX
            }
        }
        .mask {
            WindowTabStripScrollFadeMask(
                leadingFadeWidth: context.leadingFadeWidth(contentMaxX: tabScrollContentMaxX),
                trailingFadeWidth: context.trailingFadeWidth(contentMinX: tabScrollContentMinX),
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let groupDragWindowId, !isWindowTabStripDragInProgress() else { return }
            focusWindowFromTabStripClick(groupDragWindowId, fallbackWorkspace: strip.workspaceName)
        }
        .simultaneousGesture(tabScrollBackgroundGroupDragGesture(
            for: groupDragWindowId,
            context: context,
        ))
    }

}
