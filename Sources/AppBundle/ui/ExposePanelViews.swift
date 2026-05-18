import AppKit
import Common
import SwiftUI

struct ExposeView: View {
    let entries: [ExposeEntry]
    let onSelect: (UInt32) -> Void
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var expandedGroupId: String? = nil
    @State private var expandedGroupFrames: [ExposeExpandedGroupFrame] = []
    @State private var collapsedGroupFrames: [ExposeCollapsedGroupFrame] = []
    @State private var expandedGroupOriginFrame: CGRect? = nil
    @State private var thumbnails: [UInt32: NSImage] = [:]

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(appeared ? 1 : 0)
                .ignoresSafeArea()

            Color.black.opacity(appeared ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            GeometryReader { geo in
                overviewGrid(in: geo.size)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .coordinateSpace(name: exposeOverviewCoordinateSpace)
                    .onTapGesture {
                        onDismiss()
                    }
                    .onPreferenceChange(ExposeExpandedGroupFramePreferenceKey.self) { frames in
                        expandedGroupFrames = frames
                    }
                    .onPreferenceChange(ExposeCollapsedGroupFramePreferenceKey.self) { frames in
                        collapsedGroupFrames = frames
                    }
                    .onContinuousHover(coordinateSpace: .named(exposeOverviewCoordinateSpace)) { phase in
                        switch phase {
                            case .active(let location):
                                handleHover(at: location)
                            case .ended:
                                collapseExpandedGroup()
                        }
                    }
            }
            .scaleEffect(appeared ? 1 : 0.95)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { appeared = true }
        }
        .task {
            await loadThumbnailsIfNeeded()
        }
    }

    private func buildSlots() -> [ExposeSlot] {
        entries.flatMap { (e: ExposeEntry) -> [ExposeSlot] in
            switch e {
                case .window(let window):
                    return [ExposeSlot.single(window, expandedGroupId: nil, groupBadgeLabel: nil)]
                case .group(let group):
                    if group.id == expandedGroupId {
                        let orderedItems = orderedExposeItemsForExpandedGroup(group.items)
                        return orderedItems.enumerated().map { index, item in
                            ExposeSlot.single(
                                item,
                                expandedGroupId: group.id,
                                groupBadgeLabel: "\(index + 1)/\(orderedItems.count)",
                            )
                        }
                    } else {
                        return [ExposeSlot.stack(group)]
                    }
            }
        }
    }

    private func expandGroup(for frame: ExposeCollapsedGroupFrame) {
        guard expandedGroupId != frame.groupId || expandedGroupOriginFrame != frame.frame else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            expandedGroupId = frame.groupId
            expandedGroupOriginFrame = frame.frame
        }
    }

    private func collapseExpandedGroup() {
        guard expandedGroupId != nil || expandedGroupOriginFrame != nil else { return }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.92)) {
            expandedGroupId = nil
            expandedGroupOriginFrame = nil
        }
    }

    private func handleHover(at location: CGPoint) {
        if let expandedGroupId,
           shouldKeepExpandedGroupVisible(
               location: location,
               groupId: expandedGroupId,
               expandedFrames: expandedGroupFrames,
               collapsedOriginFrame: expandedGroupOriginFrame,
               padding: exposeExpandedGroupHoverPadding,
           ) {
            return
        }

        if let hoveredGroupFrame = hoveredCollapsedGroupFrame(
            at: location,
            within: collapsedGroupFrames,
            padding: 4,
        ) {
            expandGroup(for: hoveredGroupFrame)
        } else {
            collapseExpandedGroup()
        }
    }

    private func gridCols(_ totalSpan: Int, sw: CGFloat, sh: CGFloat) -> Int {
        guard totalSpan > 0 else { return 1 }
        return max(1, min(totalSpan, Int(ceil(sqrt(Double(totalSpan) * Double(sw / sh))))))
    }

    // Pack slots into rows respecting spans
    private func buildGridRows(_ slots: [ExposeSlot], cols: Int) -> [[ExposeSlot]] {
        var rows: [[ExposeSlot]] = [[]]
        var usedInRow = 0
        for slot in slots {
            if usedInRow + slot.span > cols, usedInRow > 0 {
                rows.append([])
                usedInRow = 0
            }
            rows[rows.count - 1].append(slot)
            usedInRow += slot.span
        }
        return rows.filter { !$0.isEmpty }
    }

    private func gridRows(_ slots: [ExposeSlot], cols: Int) -> Int {
        buildGridRows(slots, cols: cols).count
    }

    @ViewBuilder
    private func slotView(_ slot: ExposeSlot, ch: CGFloat) -> some View {
        switch slot {
            case .single(let window, let expandedGroupId, let groupBadgeLabel):
                let item = window.withThumbnail(thumbnails[window.id])
                let cardCw = (ch - exposeCardTitleHeight) * window.aspectRatio
                ExposeWinCard(
                    item: item,
                    cw: cardCw,
                    ch: ch,
                    badgeLabel: groupBadgeLabel,
                )
                .background {
                    if let expandedGroupId {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ExposeExpandedGroupFramePreferenceKey.self,
                                value: [ExposeExpandedGroupFrame(
                                    groupId: expandedGroupId,
                                    frame: geometry.frame(in: .named(exposeOverviewCoordinateSpace)),
                                )],
                            )
                        }
                    }
                }
                .onTapGesture { onSelect(window.id) }

            case .stack(let group):
                let cardCw = (ch - 24) * group.aspectRatio
                ExposeStackCard(group: group, thumbnails: thumbnails, cw: cardCw, ch: ch)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ExposeCollapsedGroupFramePreferenceKey.self,
                                value: [ExposeCollapsedGroupFrame(
                                    groupId: group.id,
                                    frame: geometry.frame(in: .named(exposeOverviewCoordinateSpace)),
                                )],
                            )
                        }
                    }
        }
    }

    private func overviewGrid(in viewportSize: CGSize) -> some View {
        let spacing = exposeExpandedGroupSpacing
        let slots = buildSlots()
        let cols = gridCols(max(slots.count, 1), sw: viewportSize.width, sh: viewportSize.height)
        let rows = gridRows(slots, cols: cols)
        let ch = min(280, (viewportSize.height - 80 - spacing * CGFloat(rows - 1)) / CGFloat(rows))

        return VStack(spacing: spacing) {
            let gridRows = buildGridRows(slots, cols: cols)
            ForEach(Array(gridRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row) { slot in
                        slotView(slot, ch: ch)
                    }
                }
            }
        }
    }

    @MainActor
    private func loadThumbnailsIfNeeded() async {
        try? await Task.sleep(nanoseconds: 16_000_000)
        for id in exposeThumbnailWindowIds(from: entries) where thumbnails[id] == nil {
            guard !Task.isCancelled else { return }
            if let thumbnail = captureExposeThumbnail(id) {
                thumbnails[id] = thumbnail
            }
            try? await Task.sleep(nanoseconds: 4_000_000)
        }
    }
}
