import AppKit
import Common
import SwiftUI

private let exposePanelId = "AeroSpace.expose"

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
                                viewFor(s, cw: cw, ch: ch)
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
    private func viewFor(_ s: Slot, cw: CGFloat, ch: CGFloat) -> some View {
        switch s {
            case .single(let w):
                let scaledCw = cw * max(0.4, min(1.0, w.widthRatio))
                WinCard(item: w, cw: scaledCw, ch: ch)
                    .onTapGesture { onSelect(w.id) }

            case .stack(let g):
                let scaledCw = cw * max(0.4, min(1.0, g.widthRatio))
                StackCard(group: g, cw: scaledCw, ch: ch, onExpand: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { expandedGroupId = g.id }
                })

            case .expandedGroup(let g):
                let scaledCw = cw * max(0.4, min(1.0, g.widthRatio))
                ExpandedGroupCard(group: g, cw: scaledCw, ch: ch, onSelect: onSelect, onCollapse: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { expandedGroupId = nil }
                })
                .frame(width: cw, height: ch) // lock frame to a single cell to overlay cleanly
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
    @State private var hov = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                cardThumb(item, w: cw, h: ch - 20, hov: hov)
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
                .foregroundStyle(.white.opacity(hov ? 0.95 : 0.6))
                .lineLimit(1)
                .frame(maxWidth: cw)
        }
        .frame(width: cw, height: ch)
        .onHover { hov = $0 }
        .scaleEffect(hov ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: hov)
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
        .scaleEffect(hov ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: hov)
    }
}

private struct ExpandedGroupCard: View {
    let group: ExposeTabGroup
    let cw: CGFloat
    let ch: CGFloat
    let onSelect: (UInt32) -> Void
    let onCollapse: () -> Void

    @State private var hoveredInZone = true

    var body: some View {
        HStack(spacing: 10) {
            ForEach(group.items) { item in
                WinCard(item: item, cw: cw, ch: ch, badge: true)
                    .onTapGesture { onSelect(item.id) }
            }
        }
        .padding(16) // add extra inner padding to create a larger hit zone
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
                )
        )
        // A generous invisible background extends the drop-off zone
        .background(Color.clear.padding(-40))
        .contentShape(Rectangle())
        .onHover { inZone in
            hoveredInZone = inZone
            if !inZone { onCollapse() }
        }
    }
}

// MARK: - Thumbnail

@ViewBuilder
private func cardThumb(_ item: ExposeWindowItem, w: CGFloat, h: CGFloat, hov: Bool) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.08))
        if let img = item.thumbnail {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(2)
        } else {
            Image(systemName: "macwindow")
                .font(.system(size: 24, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.1))
        }
    }
    .frame(width: w, height: h)
    .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(
                hov && item.isFocused ? Color.accentColor.opacity(0.7) :
                    (hov ? .white.opacity(0.2) : .white.opacity(0.03)),
                lineWidth: hov && item.isFocused ? 1.5 : 0.5
            )
    )
    .shadow(color: .black.opacity(hov ? 0.12 : 0.03), radius: hov ? 4 : 1, y: 1)
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
