import AppKit
import Common
import SwiftUI

struct WindowTabStripView: View {
    let strip: WindowTabStripViewModel
    let drawsChrome: Bool

    struct PendingReorderDrop: Equatable {
        let windowId: UInt32
        let sourceIndex: Int
        let targetIndex: Int
        let orderBeforeDrop: [UInt32]
    }

    @State var draggingTabId: UInt32? = nil
    @State var hoveredTabId: UInt32? = nil
    @State var dragTranslationX: CGFloat = 0
    @State var hasCommittedToDetach = false
    @State var pendingReorderDrop: PendingReorderDrop? = nil
    @State var tabScrollContentMinX: CGFloat = 0
    @Namespace var tabFeedbackNamespace
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            tabStripBody(
                stripWidth: max(proxy.size.width, 0),
                stripHeight: max(proxy.size.height, 0),
            )
        }
    }

    func tabStripBody(stripWidth: CGFloat, stripHeight: CGFloat) -> some View {
        let tabOrder = strip.tabs.map(\.windowId)
        let tabIndicesById = tabIndexLookup(for: strip.tabs)
        let count = max(strip.tabs.count, 1)
        let tabWidth = windowTabStripTabWidth(stripWidth: stripWidth, count: count)
        let itemHeight = max(stripHeight - 4, 18)
        let effectiveTabWidth = tabWidth + windowTabStripTabSpacing
        let tabContentWidth = CGFloat(strip.tabs.count) * tabWidth
            + CGFloat(max(strip.tabs.count - 1, 0)) * windowTabStripTabSpacing
            + windowTabStripContentHorizontalPadding * 2
        let shouldFadeTabScroll = tabContentWidth > windowTabStripAvailableTabsWidth(stripWidth: stripWidth) + 1
        let scrollCoordinateSpaceName = "window-tab-strip-scroll-\(strip.id.hashValue)"
        let leadingFadeWidth = windowTabLeadingScrollFadeWidth(
            isScrollable: shouldFadeTabScroll,
            contentMinX: tabScrollContentMinX,
            stripWidth: stripWidth,
        )
        let trailingFadeWidth = windowTabTrailingScrollFadeWidth(
            isScrollable: shouldFadeTabScroll,
            stripWidth: stripWidth,
        )
        let activeWindowId = strip.tabs.first(where: \.isActive)?.windowId
        let groupDragWindowId = activeWindowId ?? strip.tabs.first?.windowId
        let stripCornerRadius = strip.activeWindowCornerRadius
        let topInnerCornerRadius = windowTabGroupTopInnerCornerRadius(stripCornerRadius)
        let outerTopRadius = windowTabGroupOuterCornerRadius(innerCornerRadius: topInnerCornerRadius)
        let tabStripShape = windowTabStripShape(outerTopRadius: outerTopRadius)

        let draggingIndex = draggingTabId.flatMap { tabIndicesById[$0] }
        let targetIndex: Int? = draggingIndex.map { srcIdx in
            let delta = Int(round(dragTranslationX / effectiveTabWidth))
            return max(0, min(srcIdx + delta, strip.tabs.count - 1))
        }

        return HStack(spacing: 0) {
            WindowTabGroupHandleView(
                windowId: groupDragWindowId,
                workspaceName: strip.workspaceName
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: windowTabStripTabSpacing) {
                    let tabs = strip.tabs
                    ForEach(tabs) { tab in
                        WindowTabItemView(
                            tab: tab,
                            width: tabWidth,
                            height: itemHeight,
                            isDragSource: draggingTabId == tab.windowId,
                            isHovered: hoveredTabId == tab.windowId,
                            feedbackNamespace: tabFeedbackNamespace
                        )
                        .offset(x: tabVisualOffset(
                            for: tab,
                            draggingIndex: draggingIndex,
                            targetIndex: targetIndex,
                            effectiveTabWidth: effectiveTabWidth,
                            currentOrder: tabOrder,
                            tabIndicesById: tabIndicesById,
                        ))
                        .zIndex(draggingTabId == tab.windowId ? 1 : 0)
                        .shadow(
                            color: draggingTabId == tab.windowId ? Color.black.opacity(0.12) : Color.clear,
                            radius: draggingTabId == tab.windowId ? 6 : 0,
                            y: draggingTabId == tab.windowId ? 2 : 0,
                        )
                        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: targetIndex)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    if shouldPromoteTabStripDragToGroup(windowId: tab.windowId) {
                                        draggingTabId = nil
                                        hoveredTabId = nil
                                        dragTranslationX = 0
                                        hasCommittedToDetach = false
                                        updateMoveFromTabStrip(tab.windowId)
                                        return
                                    }
                                    if hasCommittedToDetach {
                                        updateDetachedTabFromTabStrip(tab.windowId)
                                        return
                                    }

                                    let dy = value.translation.height

                                    // If vertical drag exceeds threshold, commit to detach
                                    if abs(dy) > tabReorderVerticalEscapeThreshold, strip.tabs.count > 1 {
                                        hasCommittedToDetach = true
                                        draggingTabId = nil
                                        hoveredTabId = nil
                                        dragTranslationX = 0
                                        updateDetachedTabFromTabStrip(tab.windowId)
                                        return
                                    }

                                    draggingTabId = tab.windowId
                                    hoveredTabId = nil
                                    dragTranslationX = value.translation.width
                                }
                                .onEnded { _ in
                                    if shouldContinueCurrentGroupDrag(windowId: tab.windowId) {
                                        finishMoveFromTabStrip()
                                    } else if hasCommittedToDetach {
                                        hasCommittedToDetach = false
                                        Task { @MainActor in
                                            try? await resetManipulatedWithMouseIfPossible()
                                        }
                                    } else if let srcIdx = draggingIndex, let tgtIdx = targetIndex, srcIdx != tgtIdx {
                                        settleReorderedTab(
                                            windowId: tab.windowId,
                                            sourceIndex: srcIdx,
                                            targetIndex: tgtIdx,
                                            orderBeforeDrop: tabOrder,
                                        )
                                        reorderTabInStrip(tab.windowId, toIndex: tgtIdx)
                                        return
                                    }
                                    draggingTabId = nil
                                    hoveredTabId = nil
                                    dragTranslationX = 0
                                },
                        )
                        .onHover { hovering in
                            updateHoveredTab(tab.windowId, hovering: hovering)
                        }
                    }
                }
                .padding(.horizontal, windowTabStripContentHorizontalPadding)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: WindowTabStripScrollContentMinXPreferenceKey.self,
                            value: proxy.frame(in: .named(scrollCoordinateSpaceName)).minX,
                        )
                    }
                }
            }
            .coordinateSpace(name: scrollCoordinateSpaceName)
            .onPreferenceChange(WindowTabStripScrollContentMinXPreferenceKey.self) { nextMinX in
                guard abs(tabScrollContentMinX - nextMinX) > 0.5 else { return }
                tabScrollContentMinX = nextMinX
            }
            .mask {
                WindowTabStripScrollFadeMask(
                    leadingFadeWidth: leadingFadeWidth,
                    trailingFadeWidth: trailingFadeWidth,
                )
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in
                        guard let windowId = groupDragWindowId,
                              shouldAllowTabStripChromeGroupDrag(windowId: windowId)
                        else { return }
                        updateMoveFromTabStrip(windowId)
                    }
                    .onEnded { _ in
                        guard let windowId = groupDragWindowId,
                              shouldContinueCurrentGroupDrag(windowId: windowId)
                        else { return }
                        finishMoveFromTabStrip()
                    },
            )

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
                tabStripShape
                    .fill(mattePanelFill)
                tabStripShape
                    .strokeBorder(mattePanelBorder, lineWidth: windowTabGroupFrameStrokeWidth)
            }
        }
        .clipShape(tabStripShape)
        .animation(reduceMotion ? windowTabReducedMotionAnimation : windowTabPillAnimation, value: hoveredTabId)
        .animation(reduceMotion ? windowTabReducedMotionAnimation : windowTabPillAnimation, value: activeWindowId)
        .onChange(of: tabOrder) { newOrder in
            clearPendingReorderDropIfModelApplied(currentOrder: newOrder)
        }
    }

    func tabIndexLookup(for tabs: [WindowTabItemViewModel]) -> [UInt32: Int] {
        var result: [UInt32: Int] = [:]
        result.reserveCapacity(tabs.count)
        for (index, tab) in tabs.enumerated() {
            result[tab.windowId] = index
        }
        return result
    }

    func windowTabStripShape(outerTopRadius: CGFloat) -> WindowTabDropOutlineShape {
        WindowTabDropOutlineShape(cornerRadii: PreviewCornerRadii(
            topLeft: outerTopRadius,
            topRight: outerTopRadius,
            bottomRight: 0,
            bottomLeft: 0
        ))
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

    func tabVisualOffset(
        for tab: WindowTabItemViewModel,
        draggingIndex: Int?,
        targetIndex: Int?,
        effectiveTabWidth: CGFloat,
        currentOrder: [UInt32],
        tabIndicesById: [UInt32: Int],
    ) -> CGFloat {
        if let pendingReorderDrop, pendingReorderDrop.orderBeforeDrop == currentOrder {
            if tab.windowId == pendingReorderDrop.windowId {
                return CGFloat(pendingReorderDrop.targetIndex - pendingReorderDrop.sourceIndex) * effectiveTabWidth
            }
            guard let tabIndex = tabIndicesById[tab.windowId] else { return 0 }
            return tabShiftOffset(
                tabIndex: tabIndex,
                sourceIndex: pendingReorderDrop.sourceIndex,
                targetIndex: pendingReorderDrop.targetIndex,
                effectiveTabWidth: effectiveTabWidth,
            )
        }

        guard let draggingIndex, let targetIndex else {
            // Dragged tab follows cursor 1:1
            if tab.windowId == draggingTabId {
                return dragTranslationX
            }
            return 0
        }

        // The dragged tab follows the cursor directly
        if tab.windowId == draggingTabId {
            return dragTranslationX
        }

        guard let tabIndex = tabIndicesById[tab.windowId] else { return 0 }
        return tabShiftOffset(
            tabIndex: tabIndex,
            sourceIndex: draggingIndex,
            targetIndex: targetIndex,
            effectiveTabWidth: effectiveTabWidth,
        )
    }

    func tabShiftOffset(
        tabIndex: Int,
        sourceIndex: Int,
        targetIndex: Int,
        effectiveTabWidth: CGFloat,
    ) -> CGFloat {
        // Tabs between source and target shift to make room
        if sourceIndex < targetIndex {
            // Dragging right: tabs in (source, target] shift one slot left
            if tabIndex > sourceIndex, tabIndex <= targetIndex {
                return -effectiveTabWidth
            }
        } else if sourceIndex > targetIndex {
            // Dragging left: tabs in [target, source) shift one slot right
            if tabIndex >= targetIndex, tabIndex < sourceIndex {
                return effectiveTabWidth
            }
        }

        return 0
    }

    func settleReorderedTab(
        windowId: UInt32,
        sourceIndex: Int,
        targetIndex: Int,
        orderBeforeDrop: [UInt32],
    ) {
        pendingReorderDrop = PendingReorderDrop(
            windowId: windowId,
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            orderBeforeDrop: orderBeforeDrop,
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

    func focusTabStripChrome(windowId: UInt32?) {
        guard let windowId, !isWindowTabStripDragInProgress() else { return }
        focusWindowFromTabStripClick(windowId, fallbackWorkspace: strip.workspaceName)
    }
}

struct WindowTabStripScrollFadeMask: View {
    let leadingFadeWidth: CGFloat
    let trailingFadeWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let leadingFade = min(leadingFadeWidth, proxy.size.width / 2)
            let trailingFade = min(trailingFadeWidth, proxy.size.width / 2)
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing,
                )
                .frame(width: leadingFade)

                Rectangle()
                    .fill(Color.black)

                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing,
                )
                .frame(width: trailingFade)
            }
        }
    }
}

struct WindowTabStripScrollContentMinXPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WindowTabGroupHandleView: View {
    let windowId: UInt32?
    let workspaceName: String

    var body: some View {
        Button {
            guard let windowId, !isWindowTabStripDragInProgress() else { return }
            focusWindowFromTabStripClick(windowId, fallbackWorkspace: workspaceName)
        } label: {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Focus Tab Group")
        .frame(width: windowTabStripReservedGroupHandleWidth())
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { _ in
                    guard let windowId else { return }
                    updateMoveFromTabStrip(windowId)
                }
                .onEnded { _ in
                    finishMoveFromTabStrip()
                },
        )
    }
}

struct WindowTabOcclusionMask: Shape {
    let panelFrame: CGRect
    let occludingScreenFrames: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        for localRect in windowTabLocalOcclusionRects(
            panelFrame: panelFrame,
            occludingScreenFrames: occludingScreenFrames,
        ) {
            path.addRect(localRect)
        }
        return path
    }
}

extension View {
    func windowTabOcclusionMasked(panelFrame: CGRect, occludingScreenFrames: [CGRect]) -> some View {
        mask(
            WindowTabOcclusionMask(
                panelFrame: panelFrame,
                occludingScreenFrames: occludingScreenFrames,
            )
            .fill(style: FillStyle(eoFill: true))
        )
    }
}

