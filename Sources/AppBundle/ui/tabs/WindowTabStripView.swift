import AppKit
import SwiftUI
import Foundation

struct WindowTabStripView: View {
    let strip: WindowTabStripViewModel

    @ObservedObject var trayModel = TrayMenuModel.shared
    @State var draggingTabId: UInt32?
    @State var hoveredTabId: UInt32?
    @State var dragTranslationX: CGFloat = 0
    @State var hasCommittedToDetach = false
    @State var pendingReorderDrop: WindowTabPendingReorderDrop?
    @State var tabScrollContentMinX: CGFloat = 0
    @State var tabScrollContentMaxX: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            tabStripBody(
                stripWidth: max(proxy.size.width, 0),
                stripHeight: max(proxy.size.height, 0),
            )
        }
    }
}

extension WindowTabStripView {
    func groupDragGesture(for windowId: UInt32?) -> some Gesture {
        DragGesture(minimumDistance: windowTabStripGroupDragMinimumDistance, coordinateSpace: .global)
            .onChanged { _ in
                noteCurrentMousePointerSample()
                guard let windowId,
                      shouldAllowTabStripChromeGroupDrag(windowId: windowId)
                else { return }
                updateMoveFromTabStrip(windowId)
            }
            .onEnded { _ in
                noteCurrentMousePointerSample()
                guard let windowId,
                      shouldContinueCurrentGroupDrag(windowId: windowId)
                else { return }
                finishMoveFromTabStrip()
            }
    }

    func tabScrollBackgroundGroupDragGesture(
        for windowId: UInt32?,
        context: WindowTabStripLayoutContext,
    ) -> some Gesture {
        DragGesture(minimumDistance: windowTabStripGroupDragMinimumDistance, coordinateSpace: .local)
            .onChanged { value in
                guard isWindowTabStripScrollBackgroundDragStart(
                    localX: value.startLocation.x,
                    contentMinX: tabScrollContentMinX,
                    tabWidth: context.tabWidth,
                    tabCount: strip.tabs.count,
                ) else { return }
                noteCurrentMousePointerSample()
                guard let windowId,
                      shouldAllowTabStripChromeGroupDrag(windowId: windowId)
                else { return }
                updateMoveFromTabStrip(windowId)
            }
            .onEnded { value in
                guard isWindowTabStripScrollBackgroundDragStart(
                    localX: value.startLocation.x,
                    contentMinX: tabScrollContentMinX,
                    tabWidth: context.tabWidth,
                    tabCount: strip.tabs.count,
                ) else { return }
                noteCurrentMousePointerSample()
                guard let windowId,
                      shouldContinueCurrentGroupDrag(windowId: windowId)
                else { return }
                finishMoveFromTabStrip()
            }
    }

    func tabChromeGroupDragGesture(
        for windowId: UInt32?,
        context: WindowTabStripLayoutContext,
    ) -> some Gesture {
        DragGesture(minimumDistance: windowTabStripGroupDragMinimumDistance, coordinateSpace: .local)
            .onChanged { value in
                guard isWindowTabStripChromeGroupDragStart(
                    localX: value.startLocation.x,
                    contentMinX: tabScrollContentMinX,
                    contentMaxX: tabScrollContentMaxX,
                    tabWidth: context.tabWidth,
                    tabCount: strip.tabs.count,
                ) else { return }
                noteCurrentMousePointerSample()
                guard let windowId,
                      shouldAllowTabStripChromeGroupDrag(windowId: windowId)
                else { return }
                updateMoveFromTabStrip(windowId)
            }
            .onEnded { value in
                guard isWindowTabStripChromeGroupDragStart(
                    localX: value.startLocation.x,
                    contentMinX: tabScrollContentMinX,
                    contentMaxX: tabScrollContentMaxX,
                    tabWidth: context.tabWidth,
                    tabCount: strip.tabs.count,
                ) else { return }
                noteCurrentMousePointerSample()
                guard let windowId,
                      shouldContinueCurrentGroupDrag(windowId: windowId)
                else { return }
                finishMoveFromTabStrip()
            }
    }
}

func isWindowTabStripScrollBackgroundDragStart(
    localX: CGFloat,
    contentMinX: CGFloat,
    tabWidth: CGFloat,
    tabCount: Int,
) -> Bool {
    guard tabCount > 0 else { return true }
    let tabsStart = contentMinX + windowTabStripContentHorizontalPadding
    let tabsWidth = CGFloat(tabCount) * tabWidth
        + CGFloat(max(tabCount - 1, 0)) * windowTabStripTabSpacing
    let tabsEnd = tabsStart + tabsWidth
    return localX < tabsStart || localX > tabsEnd
}

func isWindowTabStripChromeGroupDragStart(
    localX: CGFloat,
    contentMinX: CGFloat,
    contentMaxX: CGFloat,
    tabWidth: CGFloat,
    tabCount: Int,
) -> Bool {
    guard tabCount > 0 else { return true }
    let tabsStart = contentMinX + windowTabStripContentHorizontalPadding
    let tabsWidth = CGFloat(tabCount) * tabWidth
        + CGFloat(max(tabCount - 1, 0)) * windowTabStripTabSpacing
    let tabsEnd = tabsStart + tabsWidth
    let contentIsKnown = contentMaxX > contentMinX
    if contentIsKnown, localX >= contentMinX, localX <= contentMaxX {
        return localX < tabsStart || localX > tabsEnd
    }
    return true
}

extension WindowTabStripView {
    func tabStripBody(stripWidth: CGFloat, stripHeight: CGFloat) -> some View {
        let context = WindowTabStripLayoutContext(strip: strip, width: stripWidth)
        let itemHeight = min(max(stripHeight - 10, 18), 26)
        let activeWindowId = strip.tabs.first(where: \.isActive)?.windowId
        let groupDragWindowId = activeWindowId ?? strip.tabs.first?.windowId

        return HStack(spacing: 6) {
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
        .padding(.leading, 2)
        .padding(.trailing, 8)
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
                leadingFadeWidth: context.leadingFadeWidth(contentMinX: tabScrollContentMinX),
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

extension WindowTabStripView {
    func tabDragGesture(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
    ) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                noteCurrentMousePointerSample()
                handleTabDragChanged(tab: tab, translation: value.translation)
            }
            .onEnded { _ in
                noteCurrentMousePointerSample()
                handleTabDragEnded(tab: tab, context: context)
            }
    }

    func handleTabDragChanged(tab: WindowTabItemViewModel, translation: CGSize) {
        if shouldPromoteTabStripDragToGroup(windowId: tab.windowId) {
            clearTabDragState()
            updateMoveFromTabStrip(tab.windowId)
            return
        }
        if hasCommittedToDetach {
            updateDetachedTabFromTabStrip(tab.windowId)
            return
        }
        if abs(translation.height) > tabReorderVerticalEscapeThreshold, strip.tabs.count > 1 {
            hasCommittedToDetach = true
            draggingTabId = nil
            hoveredTabId = nil
            dragTranslationX = 0
            updateDetachedTabFromTabStrip(tab.windowId)
            return
        }
        draggingTabId = tab.windowId
        hoveredTabId = nil
        dragTranslationX = translation.width
    }

    func handleTabDragEnded(tab: WindowTabItemViewModel, context: WindowTabStripLayoutContext) {
        if shouldContinueCurrentGroupDrag(windowId: tab.windowId) {
            finishMoveFromTabStrip()
        } else if hasCommittedToDetach {
            hasCommittedToDetach = false
            Task { @MainActor in
                try? await resetManipulatedWithMouseIfPossible()
            }
        } else if let srcIdx = draggingIndex(context: context),
                  let tgtIdx = reorderTargetIndex(context: context),
                  srcIdx != tgtIdx {
            settleReorderedTab(
                windowId: tab.windowId,
                sourceIndex: srcIdx,
                targetIndex: tgtIdx,
                orderBeforeDrop: context.tabOrder,
            )
            reorderTabInStrip(tab.windowId, toIndex: tgtIdx)
            return
        }
        clearTabDragState()
    }

    func clearTabDragState() {
        draggingTabId = nil
        hoveredTabId = nil
        dragTranslationX = 0
        hasCommittedToDetach = false
    }
}

extension WindowTabStripView {
    func tabVisualOffset(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
    ) -> CGFloat {
        if let reentryPreview = trayModel.windowTabReentryPreview,
           reentryPreview.stripId == strip.id,
           reentryPreview.orderBeforeDrop == context.tabOrder {
            return tabReentryVisualOffset(for: tab, context: context, drop: reentryPreview)
        }
        if let pendingReorderDrop, pendingReorderDrop.orderBeforeDrop == context.tabOrder {
            return pendingReorderOffset(for: tab, context: context, drop: pendingReorderDrop)
        }
        guard let draggingIndex = draggingIndex(context: context),
              let targetIndex = reorderTargetIndex(context: context)
        else {
            return tab.windowId == draggingTabId ? dragTranslationX : 0
        }
        if tab.windowId == draggingTabId {
            return dragTranslationX
        }
        return tabShiftOffset(
            for: tab,
            context: context,
            sourceIndex: draggingIndex,
            targetIndex: targetIndex,
        )
    }

    func draggingIndex(context: WindowTabStripLayoutContext) -> Int? {
        draggingTabId.flatMap { context.tabIndicesById[$0] }
    }

    func reorderTargetIndex(context: WindowTabStripLayoutContext) -> Int? {
        draggingIndex(context: context).map { sourceIndex in
            let delta = Int(round(dragTranslationX / context.effectiveTabWidth))
            return max(0, min(sourceIndex + delta, strip.tabs.count - 1))
        }
    }

    func pendingReorderOffset(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        drop: WindowTabPendingReorderDrop,
    ) -> CGFloat {
        if tab.windowId == drop.windowId {
            if let sourceVisualOffset = drop.sourceVisualOffset {
                return sourceVisualOffset
            }
            return CGFloat(drop.targetIndex - drop.sourceIndex) * context.effectiveTabWidth
        }
        return tabShiftOffset(
            for: tab,
            context: context,
            sourceIndex: drop.sourceIndex,
            targetIndex: drop.targetIndex,
        )
    }

    func tabReentryVisualOffset(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        drop: WindowTabPendingReorderDrop,
    ) -> CGFloat {
        if tab.windowId == drop.windowId {
            return drop.sourceVisualOffset ?? CGFloat(drop.targetIndex - drop.sourceIndex) * context.effectiveTabWidth
        }
        return tabShiftOffset(
            for: tab,
            context: context,
            sourceIndex: drop.sourceIndex,
            targetIndex: drop.targetIndex,
        )
    }

    func tabShiftOffset(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        sourceIndex: Int,
        targetIndex: Int,
    ) -> CGFloat {
        guard let tabIndex = context.tabIndicesById[tab.windowId] else { return 0 }
        if sourceIndex < targetIndex, tabIndex > sourceIndex, tabIndex <= targetIndex {
            return -context.effectiveTabWidth
        }
        if sourceIndex > targetIndex, tabIndex >= targetIndex, tabIndex < sourceIndex {
            return context.effectiveTabWidth
        }
        return 0
    }

}

extension WindowTabStripView {
    func settleReorderedTab(
        windowId: UInt32,
        sourceIndex: Int,
        targetIndex: Int,
        orderBeforeDrop: [UInt32],
    ) {
        pendingReorderDrop = WindowTabPendingReorderDrop(
            stripId: strip.id,
            windowId: windowId,
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            orderBeforeDrop: orderBeforeDrop,
            sourceVisualOffset: nil,
        )
        draggingTabId = nil
        hoveredTabId = nil
        dragTranslationX = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + windowTabReorderDropClearDelay) {
            guard pendingReorderDrop?.windowId == windowId else { return }
            pendingReorderDrop = nil
        }
    }

    func clearPendingReorderDropIfModelApplied(currentOrder: [UInt32]) {
        guard let pendingReorderDrop else { return }
        guard pendingReorderDrop.orderBeforeDrop != currentOrder else { return }
        self.pendingReorderDrop = nil
    }

    func updateHoveredTab(_ windowId: UInt32, hovering: Bool) {
        guard draggingTabId == nil, !hasCommittedToDetach else {
            hoveredTabId = nil
            return
        }
        if hovering {
            hoveredTabId = windowId
        } else if hoveredTabId == windowId {
            hoveredTabId = nil
        }
    }
}

extension WindowTabStripView {
    func tabItem(
        _ tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        itemHeight: CGFloat,
    ) -> some View {
        Button {
            guard !isWindowTabStripDragInProgress() else { return }
            focusWindowFromTabStripClick(tab.windowId, fallbackWorkspace: tab.workspaceName)
        } label: {
            WindowTabItemView(
                tab: tab,
                width: context.tabWidth,
                height: itemHeight,
                isDragSource: draggingTabId == tab.windowId,
                isHovered: hoveredTabId == tab.windowId
            )
        }
        .buttonStyle(.plain)
        .offset(x: tabVisualOffset(for: tab, context: context))
        .zIndex(draggingTabId == tab.windowId ? 1 : 0)
        .shadow(
            color: draggingTabId == tab.windowId ? Color.black.opacity(0.18) : Color.clear,
            radius: draggingTabId == tab.windowId ? 7 : 0,
            y: draggingTabId == tab.windowId ? 2 : 0,
        )
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: reorderTargetIndex(context: context))
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: trayModel.windowTabReentryPreview?.targetIndex)
        .animation(nil, value: trayModel.windowTabReentryPreview?.sourceVisualOffset)
        .highPriorityGesture(tabDragGesture(for: tab, context: context))
        .workspaceSidebarDrag(enabled: true) {
            WorkspaceSidebarDragPayload.window(tab.windowId).itemProvider
        }
        .onHover { hovering in
            updateHoveredTab(tab.windowId, hovering: hovering)
        }
        .contextMenu {
            Button("Remove Tab From Stack") {
                removeWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
            }
        }
    }
}
