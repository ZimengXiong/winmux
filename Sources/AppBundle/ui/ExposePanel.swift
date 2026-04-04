import AppKit
import Common
import SwiftUI

private let exposePanelId = "AeroSpace.expose"
private let exposeExpandedGroupHoverCoordinateSpace = "AeroSpace.expose.expandedGroupHover"
private let exposeCardTitleHeight: CGFloat = 20
private let exposeExpandedGroupSpacing: CGFloat = 16
private let exposeExpandedGroupHoverPadding: CGFloat = 60
private let exposeExpandedGroupViewportMargin = CGSize(width: 96, height: 96)

struct ExposeHoverTargetFrame: Equatable {
    let itemId: UInt32
    let frame: CGRect
}

struct ExposeHoverTargetPreferenceKey: PreferenceKey {
    static let defaultValue: [ExposeHoverTargetFrame] = []

    static func reduce(value: inout [ExposeHoverTargetFrame], nextValue: () -> [ExposeHoverTargetFrame]) {
        value.append(contentsOf: nextValue())
    }
}

func hoveredExposeItemId(at location: CGPoint, within frames: [ExposeHoverTargetFrame]) -> UInt32? {
    frames.last(where: { $0.frame.contains(location) })?.itemId
}

struct ExposeExpandedGroupLayout: Equatable {
    let columns: Int
    let rowCount: Int
    let mainCardWidth: CGFloat
    let mainCardHeight: CGFloat
    let secondaryCardWidth: CGFloat
    let secondaryCardHeight: CGFloat
    let totalSize: CGSize
}

private func exposeExpandedGroupSecondaryScale(for othersCount: Int) -> CGFloat {
    switch othersCount {
        case 0: 0
        case 1: 0.86
        case 2...4: 0.76
        case 5...6: 0.68
        default: 0.62
    }
}

private func exposeCardWidth(cardHeight: CGFloat, aspectRatio: CGFloat) -> CGFloat {
    max(1, (cardHeight - exposeCardTitleHeight) * aspectRatio)
}

func bestExposeExpandedGroupLayout(
    itemCount: Int,
    aspectRatio: CGFloat,
    viewportSize: CGSize,
    minimumMainCardHeight: CGFloat,
) -> ExposeExpandedGroupLayout {
    let safeItemCount = max(itemCount, 1)
    let othersCount = max(0, safeItemCount - 1)
    let safeAspectRatio = max(aspectRatio, 0.2)
    let availableWidth = max(200, viewportSize.width - exposeExpandedGroupViewportMargin.width)
    let availableHeight = max(minimumMainCardHeight, viewportSize.height - exposeExpandedGroupViewportMargin.height)
    let minimumMainHeight = min(max(exposeCardTitleHeight + 1, minimumMainCardHeight), availableHeight)

    func makeLayout(mainCardHeight: CGFloat, columns: Int, rowCount: Int, secondaryScale: CGFloat) -> ExposeExpandedGroupLayout {
        let secondaryCardHeight = othersCount > 0 ? mainCardHeight * secondaryScale : 0
        let mainCardWidth = exposeCardWidth(cardHeight: mainCardHeight, aspectRatio: safeAspectRatio)
        let secondaryCardWidth = othersCount > 0
            ? exposeCardWidth(cardHeight: secondaryCardHeight, aspectRatio: safeAspectRatio)
            : 0
        let gridWidth = othersCount > 0
            ? CGFloat(columns) * secondaryCardWidth + CGFloat(columns - 1) * exposeExpandedGroupSpacing
            : 0
        let gridHeight = othersCount > 0
            ? CGFloat(rowCount) * secondaryCardHeight + CGFloat(rowCount - 1) * exposeExpandedGroupSpacing
            : 0
        let totalHeight = mainCardHeight + (othersCount > 0 ? exposeExpandedGroupSpacing + gridHeight : 0)
        return ExposeExpandedGroupLayout(
            columns: columns,
            rowCount: rowCount,
            mainCardWidth: mainCardWidth,
            mainCardHeight: mainCardHeight,
            secondaryCardWidth: secondaryCardWidth,
            secondaryCardHeight: secondaryCardHeight,
            totalSize: CGSize(width: max(mainCardWidth, gridWidth), height: totalHeight),
        )
    }

    if othersCount == 0 {
        let maxMainHeightForWidth = availableWidth / safeAspectRatio + exposeCardTitleHeight
        let mainCardHeight = max(minimumMainHeight, floor(min(availableHeight, maxMainHeightForWidth)))
        return makeLayout(mainCardHeight: mainCardHeight, columns: 1, rowCount: 0, secondaryScale: 0)
    }

    let secondaryScale = exposeExpandedGroupSecondaryScale(for: othersCount)
    let maxColumns = max(1, othersCount)
    var bestLayout: ExposeExpandedGroupLayout? = nil
    var bestArea: CGFloat = -.greatestFiniteMagnitude

    for columns in 1...maxColumns {
        let rowCount = Int(ceil(Double(othersCount) / Double(columns)))
        let widthForCells = availableWidth - CGFloat(columns - 1) * exposeExpandedGroupSpacing
        guard widthForCells > 0 else { continue }

        let maxMainHeightForWidth = availableWidth / safeAspectRatio + exposeCardTitleHeight
        let maxMainHeightForGridWidth =
            (widthForCells / CGFloat(columns) / safeAspectRatio + exposeCardTitleHeight) / secondaryScale
        let maxMainHeightForHeight =
            (availableHeight - CGFloat(rowCount) * exposeExpandedGroupSpacing) /
                (1 + CGFloat(rowCount) * secondaryScale)

        let mainCardHeight = floor(min(
            maxMainHeightForWidth,
            maxMainHeightForGridWidth,
            maxMainHeightForHeight,
        ))
        guard mainCardHeight >= minimumMainHeight else { continue }

        let candidate = makeLayout(
            mainCardHeight: mainCardHeight,
            columns: columns,
            rowCount: rowCount,
            secondaryScale: secondaryScale,
        )
        let candidateArea = candidate.totalSize.width * candidate.totalSize.height
        if candidateArea > bestArea {
            bestArea = candidateArea
            bestLayout = candidate
        }
    }

    if let bestLayout {
        return bestLayout
    }

    return makeLayout(
        mainCardHeight: minimumMainHeight,
        columns: min(othersCount, 4),
        rowCount: Int(ceil(Double(othersCount) / Double(min(othersCount, 4)))),
        secondaryScale: secondaryScale,
    )
}

// MARK: - Data

struct ExposeWindowItem: Identifiable {
    let id: UInt32
    let title: String
    let appName: String
    let thumbnail: NSImage?
    let aspectRatio: CGFloat
    let isFocused: Bool
    /// Fraction of screen width this window occupies (0…1). 1.0 = full-width.
    let widthRatio: CGFloat
}

struct ExposeTabGroup: Identifiable {
    let id: String
    let items: [ExposeWindowItem]
    let aspectRatio: CGFloat
    let widthRatio: CGFloat
}

enum ExposeEntry: Identifiable {
    case window(ExposeWindowItem)
    case group(ExposeTabGroup)
    var id: String {
        switch self {
            case .window(let w): "w-\(w.id)"
            case .group(let g): "g-\(g.id)"
        }
    }
}

// MARK: - Panel

@MainActor
final class ExposePanel: NSPanelHud {
    static let shared = ExposePanel()
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private(set) var isExposeActive = false

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(exposePanelId)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func toggle() { if isExposeActive { dismiss() } else { show() } }

    func show() {
        guard !isExposeActive else { return }
        isExposeActive = true
        let ws = focus.workspace
        let fid = focus.windowOrNil?.windowId
        let screenWidth = ws.workspaceMonitor.visibleRectPaddedByOuterGaps.width
        var entries = buildEntries(from: ws.rootTilingContainer, focusedWindowId: fid, screenWidth: screenWidth)
        for w in ws.floatingWindows where w.isBound {
            entries.append(.window(makeItem(for: w, focusedWindowId: fid, screenWidth: screenWidth)))
        }
        let scr = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        setFrame(scr, display: true, animate: false)
        hostingView.rootView = AnyView(
            ExposeView(entries: entries, onSelect: { [weak self] id in self?.sel(id) },
                       onDismiss: { [weak self] in self?.dismiss() })
        )
        orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        makeKey()
    }

    func dismiss() {
        guard isExposeActive else { return }
        isExposeActive = false
        orderOut(nil)
        hostingView.rootView = AnyView(EmptyView())
    }

    private func sel(_ wid: UInt32) {
        dismiss()
        Task { @MainActor in
            guard let tok: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.menuBarButton, tok) {
                guard let w = Window.get(byId: wid), let lf = w.toLiveFocusOrNil() else { return }
                _ = setFocus(to: lf)
                w.nativeFocus()
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.keyCode == 36 { dismiss(); return }
        if event.modifierFlags.contains(.control), event.keyCode == 34 { dismiss(); return }
        super.keyDown(with: event)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Tree walk

@MainActor
private func buildEntries(from node: TreeNode, focusedWindowId: UInt32?, screenWidth: CGFloat) -> [ExposeEntry] {
    switch node.nodeCases {
        case .window(let w):
            guard w.isBound else { return [] }
            return [.window(makeItem(for: w, focusedWindowId: focusedWindowId, screenWidth: screenWidth))]
        case .tilingContainer(let c):
            if c.layout == .accordion, c.children.count > 1 {
                let ws = c.allLeafWindowsRecursive.filter(\.isBound)
                guard !ws.isEmpty else { return [] }
                let items = ws.map { makeItem(for: $0, focusedWindowId: focusedWindowId, screenWidth: screenWidth) }
                let rep = c.mostRecentWindowRecursive ?? ws[0]
                let ar = rep.lastAppliedLayoutPhysicalRect.map { $0.width / $0.height } ?? 1.5
                let wr: CGFloat = rep.lastAppliedLayoutPhysicalRect.map { $0.width / max(1, screenWidth) } ?? 1.0
                return [.group(ExposeTabGroup(id: "tg-\(rep.windowId)", items: items, aspectRatio: ar, widthRatio: wr))]
            }
            return c.children.flatMap { buildEntries(from: $0, focusedWindowId: focusedWindowId, screenWidth: screenWidth) }
        case .workspace(let ws):
            return buildEntries(from: ws.rootTilingContainer, focusedWindowId: focusedWindowId, screenWidth: screenWidth)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return []
    }
}

@MainActor
private func makeItem(for w: Window, focusedWindowId: UInt32?, screenWidth: CGFloat) -> ExposeWindowItem {
    let mw = w.asMacWindow()
    let th = captureThumb(mw.windowId)
    let ar: CGFloat = w.lastAppliedLayoutPhysicalRect.map { $0.width / $0.height } ?? 1.5
    let wr: CGFloat = w.lastAppliedLayoutPhysicalRect.map { $0.width / max(1, screenWidth) } ?? 1.0
    return ExposeWindowItem(id: mw.windowId, title: sidebarDisplayLabel(for: w),
                            appName: w.app.name ?? "Unknown", thumbnail: th,
                            aspectRatio: ar, isFocused: mw.windowId == focusedWindowId,
                            widthRatio: wr)
}

private func captureThumb(_ wid: UInt32) -> NSImage? {
    guard let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(wid),
                                           [.boundsIgnoreFraming, .nominalResolution]) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

// MARK: - View

private struct ExposeView: View {
    let entries: [ExposeEntry]
    let onSelect: (UInt32) -> Void
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var expandedGroupId: String? = nil

    var body: some View {
        ZStack {
            // Frosted backdrop
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(appeared ? 1 : 0)
                .ignoresSafeArea()

            Color.black.opacity(appeared ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    if expandedGroupId != nil {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { expandedGroupId = nil }
                    } else { onDismiss() }
                }

            GeometryReader { geo in
                let spacing: CGFloat = 16
                let slots = buildSlots()
                let n = slotWidth(slots)
                let cols = gridCols(n, sw: geo.size.width, sh: geo.size.height)
                let rows = gridRows(slots, cols: cols)
                let baseCw = min(400, (geo.size.width - 80 - spacing * CGFloat(cols - 1)) / CGFloat(cols))
                let cw = baseCw
                let ch = min(280, (geo.size.height - 80 - spacing * CGFloat(rows - 1)) / CGFloat(rows))

                VStack(spacing: spacing) {
                    let gridRows = buildGridRows(slots, cols: cols)
                    ForEach(Array(gridRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: spacing) {
                            ForEach(row) { s in
                                viewFor(s, cw: cw, ch: ch, viewportSize: geo.size)
                                    .zIndex(s.isExpandedGroup ? 1 : 0)
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .scaleEffect(appeared ? 1 : 0.95)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { appeared = true }
        }
    }

    // -- Slots --

    private enum Slot: Identifiable {
        case single(ExposeWindowItem)
        case stack(ExposeTabGroup)
        case expandedGroup(ExposeTabGroup)

        var id: String {
            switch self {
                case .single(let w): "w-\(w.id)"
                case .stack(let g): "g-\(g.id)"
                case .expandedGroup(let g): "eg-\(g.id)"
            }
        }

        // How many grid columns this slot takes
        var span: Int {
            return 1 // Never reflow the grid on expand
        }

        var isExpandedGroup: Bool {
            if case .expandedGroup = self { return true }
            return false
        }
    }

    private func buildSlots() -> [Slot] {
        entries.map { e in
            switch e {
                case .window(let w): .single(w)
                case .group(let g): g.id == expandedGroupId ? .expandedGroup(g) : .stack(g)
            }
        }
    }

    // Total "width units" across all slots
    private func slotWidth(_ slots: [Slot]) -> Int {
        slots.reduce(0) { $0 + $1.span }
    }

    private func gridCols(_ totalSpan: Int, sw: CGFloat, sh: CGFloat) -> Int {
        guard totalSpan > 0 else { return 1 }
        return max(1, min(totalSpan, Int(ceil(sqrt(Double(totalSpan) * Double(sw / sh))))))
    }

    // Pack slots into rows respecting spans
    private func buildGridRows(_ slots: [Slot], cols: Int) -> [[Slot]] {
        var rows: [[Slot]] = [[]]
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

    private func gridRows(_ slots: [Slot], cols: Int) -> Int {
        buildGridRows(slots, cols: cols).count
    }

    // -- Card dispatch --

    @ViewBuilder
    private func viewFor(_ s: Slot, cw: CGFloat, ch: CGFloat, viewportSize: CGSize) -> some View {
        switch s {
            case .single(let w):
                let cardCw = (ch - 20) * w.aspectRatio
                WinCard(item: w, cw: cardCw, ch: ch)
                    .onTapGesture { onSelect(w.id) }

            case .stack(let g):
                let cardCw = (ch - 24) * g.aspectRatio
                StackCard(group: g, cw: cardCw, ch: ch, onExpand: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { expandedGroupId = g.id }
                })

            case .expandedGroup(let g):
                let cardCw = (ch - 24) * g.aspectRatio
                ExpandedGroupCard(group: g, ch: ch, viewportSize: viewportSize, onSelect: onSelect, onCollapse: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { expandedGroupId = nil }
                })
                .frame(width: cardCw + 30, height: ch) // lock frame footprint so identical to StackCard footprint
        }
    }
}

// MARK: - NSVisualEffectView bridge

private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}

// MARK: - Window Card

private struct WinCard: View {
    let item: ExposeWindowItem
    let cw: CGFloat
    let ch: CGFloat
    var badge: Bool = false
    var hoverOverride: Bool? = nil
    @State private var localHover = false

    private var isHovered: Bool { hoverOverride ?? localHover }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                cardThumb(item, w: cw, h: ch - 20, hov: isHovered)
                if badge {
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.accentColor))
                        .padding(5)
                }
            }
            Text(item.title)
                .font(.system(size: 11, weight: item.isFocused ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isHovered ? 0.95 : 0.6))
                .lineLimit(1)
                .frame(maxWidth: cw)
        }
        .frame(width: cw, height: ch)
        .contentShape(Rectangle())
        .onHover { hovering in
            guard hoverOverride == nil else { return }
            localHover = hovering
        }
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Stack Card (collapsed group)

private struct StackCard: View {
    let group: ExposeTabGroup
    let cw: CGFloat
    let ch: CGFloat
    let onExpand: () -> Void
    @State private var hov = false

    /// Which item in the group is the focused/active one
    private var activeIndex: Int {
        group.items.firstIndex(where: \.isFocused) ?? 0
    }

    var body: some View {
        let vis = Array(group.items.prefix(4))
        let thumbH = ch - 24

        VStack(spacing: 4) {
            ZStack {
                ForEach(Array(vis.enumerated().reversed()), id: \.element.id) { i, item in
                    let isActive = (i == activeIndex)
                    let depthIndex = abs(i - activeIndex)
                    let cardW = cw - CGFloat(depthIndex) * 8
                    let cardH = thumbH - CGFloat(depthIndex) * 4

                    cardThumb(item, w: cardW, h: cardH, hov: isActive && hov)
                        // Cascade offset: items behind fan out to the right and down
                        .offset(
                            x: CGFloat(depthIndex) * 10,
                            y: CGFloat(depthIndex) * 4
                        )
                        // 3D tilt for depth perception
                        .rotation3DEffect(
                            .degrees(Double(depthIndex) * -4),
                            axis: (x: 0.15, y: 1.0, z: 0.0),
                            anchor: .leading,
                            perspective: 0.4
                        )
                        // Active item at full opacity, others dimmed
                        .opacity(isActive ? 1.0 : max(0.3, 1.0 - Double(depthIndex) * 0.25))
                        .zIndex(Double(vis.count - depthIndex))
                }
            }
            .frame(width: cw + 30, height: thumbH)
            .overlay(alignment: .bottomTrailing) {
                Text("\(group.items.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.accentColor))
                    .offset(x: 6, y: 6)
            }

            Text(group.items[safe: activeIndex]?.title ?? group.items.first?.title ?? "Group")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(hov ? 0.95 : 0.6))
                .lineLimit(1)
                .frame(maxWidth: cw)
        }
        .frame(width: cw + 30, height: ch)
        .contentShape(Rectangle())
        .onHover { hovering in
            hov = hovering
            if hovering { onExpand() }
        }
        .animation(.easeOut(duration: 0.12), value: hov)
    }
}

private struct ExpandedGroupCard: View {
    let group: ExposeTabGroup
    let ch: CGFloat
    let viewportSize: CGSize
    let onSelect: (UInt32) -> Void
    let onCollapse: () -> Void

    @State private var hoveredItemId: UInt32? = nil
    @State private var hoverFrames: [ExposeHoverTargetFrame] = []

    var body: some View {
        let activeIndex = group.items.firstIndex(where: \.isFocused) ?? 0
        let activeItem = group.items[activeIndex]

        let others = group.items.enumerated().filter { $0.offset != activeIndex }.map { $0.element }
        let count = others.count
        let layout = bestExposeExpandedGroupLayout(
            itemCount: group.items.count,
            aspectRatio: group.aspectRatio,
            viewportSize: viewportSize,
            minimumMainCardHeight: ch,
        )
        let spacing = exposeExpandedGroupSpacing

        let rowCount = layout.rowCount

        let rows: [[ExposeWindowItem]] = (0..<rowCount).map { r in
            let start = r * layout.columns
            let end = min(start + layout.columns, count)
            return Array(others[start..<end])
        }
        let totalW = layout.totalSize.width
        let totalH = layout.totalSize.height

        ZStack {
            Color.clear
                .frame(
                    width: totalW + (exposeExpandedGroupHoverPadding * 2),
                    height: totalH + (exposeExpandedGroupHoverPadding * 2),
                )

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
                .frame(width: totalW + 40, height: totalH + 40)

            VStack(spacing: spacing) {
                let isMainHovered = hoveredItemId == activeItem.id
                WinCard(
                    item: activeItem,
                    cw: layout.mainCardWidth,
                    ch: layout.mainCardHeight,
                    badge: false,
                    hoverOverride: isMainHovered,
                )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: (hoveredItemId == nil || isMainHovered) ? 3 : 0)
                            .opacity((hoveredItemId == nil || isMainHovered) ? 1.0 : 0.0)
                    )
                    .opacity(isMainHovered ? 1.0 : (hoveredItemId == nil ? 1.0 : 0.4))
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ExposeHoverTargetPreferenceKey.self,
                                value: [ExposeHoverTargetFrame(
                                    itemId: activeItem.id,
                                    frame: geometry.frame(in: .named(exposeExpandedGroupHoverCoordinateSpace)),
                                )],
                            )
                        }
                    }
                    .onTapGesture { onSelect(activeItem.id) }

                if count > 0 {
                    VStack(spacing: spacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: spacing) {
                                ForEach(row) { item in
                                    let isItemHovered = hoveredItemId == item.id

                                    WinCard(
                                        item: item,
                                        cw: layout.secondaryCardWidth,
                                        ch: layout.secondaryCardHeight,
                                        badge: false,
                                        hoverOverride: isItemHovered,
                                    )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(Color.accentColor, lineWidth: isItemHovered ? 3 : 0)
                                                .opacity(isItemHovered ? 1.0 : 0.0)
                                        )
                                        .opacity(isItemHovered ? 1.0 : (hoveredItemId == nil ? 1.0 : 0.4))
                                        .background {
                                            GeometryReader { geometry in
                                                Color.clear.preference(
                                                    key: ExposeHoverTargetPreferenceKey.self,
                                                    value: [ExposeHoverTargetFrame(
                                                        itemId: item.id,
                                                        frame: geometry.frame(in: .named(exposeExpandedGroupHoverCoordinateSpace)),
                                                    )],
                                                )
                                            }
                                        }
                                        .onTapGesture { onSelect(item.id) }
                                }
                                if row.count < layout.columns {
                                    ForEach(0..<(layout.columns - row.count), id: \.self) { _ in
                                        Color.clear.frame(
                                            width: layout.secondaryCardWidth,
                                            height: layout.secondaryCardHeight,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .animation(.easeOut(duration: 0.1), value: hoveredItemId)
        }
        .contentShape(Rectangle())
        .coordinateSpace(name: exposeExpandedGroupHoverCoordinateSpace)
        .onPreferenceChange(ExposeHoverTargetPreferenceKey.self) { hoverFrames in
            self.hoverFrames = hoverFrames
        }
        .onContinuousHover(coordinateSpace: .named(exposeExpandedGroupHoverCoordinateSpace)) { phase in
            switch phase {
                case .active(let location):
                    hoveredItemId = hoveredExposeItemId(at: location, within: hoverFrames)
                case .ended:
                    hoveredItemId = nil
                    onCollapse()
            }
        }
        .offset(y: count > 0 ? ((layout.secondaryCardHeight * CGFloat(rowCount)) + (CGFloat(max(rowCount - 1, 0)) * spacing) + spacing) / 2.0 : 0)
    }
}

// MARK: - Thumbnail

@ViewBuilder
private func cardThumb(_ item: ExposeWindowItem, w: CGFloat, h: CGFloat, hov: Bool) -> some View {
    Group {
        if let img = item.thumbnail {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.1))
                .overlay(
                    Image(systemName: "macwindow")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.1))
                )
        }
    }
    .frame(width: w, height: h)
    .shadow(color: .black.opacity(hov ? 0.35 : 0.15), radius: hov ? 12 : 6, y: hov ? 6 : 2)
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
