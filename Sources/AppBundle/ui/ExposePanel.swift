import AppKit
import Common
import SwiftUI

private let exposePanelId = "AeroSpace.expose"
private let exposeOverviewCoordinateSpace = "AeroSpace.expose.overview"
private let exposeCardTitleHeight: CGFloat = 20
private let exposeExpandedGroupSpacing: CGFloat = 16
private let exposeExpandedGroupHoverPadding: CGFloat = 26

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

struct ExposeExpandedGroupFrame: Equatable {
    let groupId: String
    let frame: CGRect
}

struct ExposeCollapsedGroupFrame: Equatable {
    let groupId: String
    let frame: CGRect
}

struct ExposeExpandedGroupFramePreferenceKey: PreferenceKey {
    static let defaultValue: [ExposeExpandedGroupFrame] = []

    static func reduce(value: inout [ExposeExpandedGroupFrame], nextValue: () -> [ExposeExpandedGroupFrame]) {
        value.append(contentsOf: nextValue())
    }
}

struct ExposeCollapsedGroupFramePreferenceKey: PreferenceKey {
    static let defaultValue: [ExposeCollapsedGroupFrame] = []

    static func reduce(value: inout [ExposeCollapsedGroupFrame], nextValue: () -> [ExposeCollapsedGroupFrame]) {
        value.append(contentsOf: nextValue())
    }
}

func exposeExpandedGroupHoverRect(
    groupId: String,
    within frames: [ExposeExpandedGroupFrame],
    padding: CGFloat,
) -> CGRect? {
    let groupFrames = frames
        .filter { $0.groupId == groupId }
        .map(\.frame)
    guard let first = groupFrames.first else { return nil }
    let union = groupFrames.dropFirst().reduce(first) { $0.union($1) }
    return union.insetBy(dx: -padding, dy: -padding)
}

func shouldKeepExpandedGroupVisible(
    location: CGPoint,
    groupId: String,
    expandedFrames: [ExposeExpandedGroupFrame],
    collapsedOriginFrame: CGRect?,
    padding: CGFloat,
) -> Bool {
    if let collapsedOriginFrame,
       collapsedOriginFrame.insetBy(dx: -padding, dy: -padding).contains(location) {
        return true
    }
    if let expandedRect = exposeExpandedGroupHoverRect(
        groupId: groupId,
        within: expandedFrames,
        padding: padding,
    ) {
        return expandedRect.contains(location)
    }
    return false
}

func hoveredCollapsedGroupFrame(
    at location: CGPoint,
    within frames: [ExposeCollapsedGroupFrame],
    padding: CGFloat = 0,
) -> ExposeCollapsedGroupFrame? {
    frames.last(where: { $0.frame.insetBy(dx: -padding, dy: -padding).contains(location) })
}

func orderedExposeItemsForExpandedGroup(_ items: [ExposeWindowItem]) -> [ExposeWindowItem] {
    guard let focusedIndex = items.firstIndex(where: \.isFocused) else { return items }
    var ordered = items
    let focusedItem = ordered.remove(at: focusedIndex)
    ordered.insert(focusedItem, at: 0)
    return ordered
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
    @State private var expandedGroupFrames: [ExposeExpandedGroupFrame] = []
    @State private var collapsedGroupFrames: [ExposeCollapsedGroupFrame] = []
    @State private var expandedGroupOriginFrame: CGRect? = nil

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
    }

    // -- Slots --

    private enum Slot: Identifiable {
        case single(ExposeWindowItem, expandedGroupId: String?, groupBadgeLabel: String?)
        case stack(ExposeTabGroup)

        var id: String {
            switch self {
                case .single(let w, let expandedGroupId, _):
                    if let expandedGroupId { return "eg-\(expandedGroupId)-\(w.id)" }
                    return "w-\(w.id)"
                case .stack(let g): return "g-\(g.id)"
            }
        }

        var span: Int {
            1
        }
    }

    private func buildSlots() -> [Slot] {
        entries.flatMap { (e: ExposeEntry) -> [Slot] in
            switch e {
                case .window(let window):
                    return [Slot.single(window, expandedGroupId: nil, groupBadgeLabel: nil)]
                case .group(let group):
                    if group.id == expandedGroupId {
                        let orderedItems = orderedExposeItemsForExpandedGroup(group.items)
                        return orderedItems.enumerated().map { index, item in
                            Slot.single(
                                item,
                                expandedGroupId: group.id,
                                groupBadgeLabel: "\(index + 1)/\(orderedItems.count)",
                            )
                        }
                    } else {
                        return [Slot.stack(group)]
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

    @ViewBuilder
    private func slotView(_ slot: Slot, ch: CGFloat) -> some View {
        switch slot {
            case .single(let window, let expandedGroupId, let groupBadgeLabel):
                let cardCw = (ch - exposeCardTitleHeight) * window.aspectRatio
                WinCard(
                    item: window,
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
                StackCard(group: group, cw: cardCw, ch: ch)
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
    var badgeLabel: String? = nil
    var hoverOverride: Bool? = nil
    @State private var localHover = false

    private var isHovered: Bool { hoverOverride ?? localHover }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                cardThumb(item, w: cw, h: ch - 20, hov: isHovered)
                if let badgeLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(badgeLabel)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor))
                    .padding(6)
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
        }
        .animation(.easeOut(duration: 0.12), value: hov)
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
