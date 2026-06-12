import AppKit
import Common
import SwiftUI

private let switcherPalettePanelId = "WinMux.switcherPalette"
private let switcherPaletteWidth: CGFloat = 560
private let switcherPaletteMaxHeight: CGFloat = 440

struct SwitcherPaletteItem: Identifiable {
    let id: UInt32
    let title: String
    let appName: String
    let icon: NSImage?
    let workspaceName: String
    let isFocused: Bool
}

// MARK: - Panel

@MainActor
final class SwitcherPaletteModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { selection = 0 } }
    }
    @Published var selection = 0
    var items: [SwitcherPaletteItem] = []
    var onSelect: ((UInt32) -> Void)? = nil

    var results: [SwitcherPaletteItem] { filterSwitcherPaletteItems(items, query: query) }

    func moveSelection(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
    }

    func selectCurrent() {
        let results = results
        guard results.indices.contains(selection) else { return }
        onSelect?(results[selection].id)
    }
}

@MainActor
final class SwitcherPalettePanel: NSPanelHud {
    static let shared = SwitcherPalettePanel()
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let model = SwitcherPaletteModel()
    private(set) var isPaletteActive = false

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(switcherPalettePanelId)
        hasShadow = true
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = .clear
        applyWinMuxLayer(.overlay)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func toggle() { if isPaletteActive { dismiss() } else { show() } }

    func show() {
        guard !isPaletteActive else { return }
        isPaletteActive = true
        model.items = buildSwitcherPaletteItems()
        model.query = ""
        model.selection = 0
        model.onSelect = { [weak self] id in self?.select(id) }
        let monitorRect = focus.workspace.workspaceMonitor.visibleRect
        // Center horizontally on the focused monitor, top edge at ~1/4 of its height
        // (converting top-left-origin coordinates back to AppKit's bottom-left origin).
        setFrame(
            NSRect(
                x: monitorRect.topLeftX + (monitorRect.width - switcherPaletteWidth) / 2,
                y: appKitScreenMaxY() - monitorRect.topLeftY - monitorRect.height * 0.25 - switcherPaletteMaxHeight,
                width: switcherPaletteWidth,
                height: switcherPaletteMaxHeight,
            ),
            display: true,
            animate: false,
        )
        hostingView.rootView = AnyView(SwitcherPaletteView(model: model))
        orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        makeKey()
    }

    func dismiss() {
        guard isPaletteActive else { return }
        isPaletteActive = false
        orderOut(nil)
        hostingView.rootView = AnyView(EmptyView())
    }

    private func select(_ windowId: UInt32) {
        dismiss()
        Task { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.menuBarButton, token) {
                guard let window = Window.get(byId: windowId), let liveFocus = window.toLiveFocusOrNil() else { return }
                window.markAsMostRecentChild()
                _ = setFocus(to: liveFocus)
                window.nativeFocus()
            }
        }
    }

    // Intercept navigation keys before the field editor consumes them; everything else
    // (typing) flows to the search field as usual.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, isPaletteActive {
            switch event.keyCode {
                case 53: dismiss(); return // esc
                case 125: model.moveSelection(1); return // down arrow
                case 126: model.moveSelection(-1); return // up arrow
                case 36, 76: model.selectCurrent(); return // return / keypad enter
                default: break
            }
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private func appKitScreenMaxY() -> CGFloat {
    NSScreen.screens.first?.frame.maxY ?? 0
}

@MainActor
private func buildSwitcherPaletteItems() -> [SwitcherPaletteItem] {
    let focusedWindowId = focus.windowOrNil?.windowId
    let focusedWorkspace = focus.workspace
    // Focused workspace first, then the rest — so an empty query shows nearby windows on top.
    let workspaces = [focusedWorkspace] + Workspace.all.filter { $0 != focusedWorkspace }
    return workspaces.flatMap { workspace in
        workspace.allLeafWindowsRecursive.filter(\.isBound).map { window in
            SwitcherPaletteItem(
                id: window.windowId,
                title: sidebarDisplayLabel(for: window),
                appName: window.app.name ?? "Unknown",
                icon: (window as? MacWindow)?.macApp.nsApp.icon,
                workspaceName: workspace.name,
                isFocused: window.windowId == focusedWindowId,
            )
        }
    }
}

// MARK: - Fuzzy matching

func switcherPaletteFuzzyScore(_ needle: String, in haystack: String) -> Int? {
    var score = 0
    var previousMatched = false
    var previousChar: Character? = nil
    var index = haystack.startIndex
    for char in needle {
        var found = false
        while index < haystack.endIndex {
            let candidate = haystack[index]
            let isWordStart = previousChar == nil || previousChar == " " || previousChar == "-" || previousChar == "." || previousChar == "/"
            previousChar = candidate
            index = haystack.index(after: index)
            if candidate == char {
                score += previousMatched ? 2 : (isWordStart ? 3 : 1)
                previousMatched = true
                found = true
                break
            }
            previousMatched = false
        }
        if !found { return nil }
    }
    return score
}

func filterSwitcherPaletteItems(_ items: [SwitcherPaletteItem], query: String) -> [SwitcherPaletteItem] {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return items }
    return items
        .compactMap { item in
            switcherPaletteFuzzyScore(needle, in: "\(item.appName) \(item.title) \(item.workspaceName)".lowercased())
                .map { (item, $0) }
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
}

// MARK: - View

struct SwitcherPaletteView: View {
    @ObservedObject var model: SwitcherPaletteModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(GlassToken.textTertiary))
                TextField("Search windows…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(GlassToken.textPrimary))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Rectangle()
                .fill(Color.white.opacity(GlassToken.separatorOpacity))
                .frame(height: StrokeToken.hairline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            SwitcherPaletteRow(item: item, isSelected: index == model.selection)
                                .id(item.id)
                                .onTapGesture { model.onSelect?(item.id) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selection) { newSelection in
                    if results.indices.contains(newSelection) {
                        proxy.scrollTo(results[newSelection].id, anchor: nil)
                    }
                }
            }
            .frame(maxHeight: switcherPaletteMaxHeight - 44)
        }
        .frame(width: switcherPaletteWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GlassSurface(shape: RoundedRectangle(cornerRadius: RadiusToken.panel, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: RadiusToken.panel, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { searchFocused = true }
    }
}

private struct SwitcherPaletteRow: View {
    let item: SwitcherPaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 13))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color.white.opacity(GlassToken.textTertiary))
            }
            Text(item.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(Color.white.opacity(isSelected ? GlassToken.textPrimary : GlassToken.textSecondary))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(item.workspaceName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(GlassToken.textQuaternary))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: RadiusToken.row, style: .continuous)
                .fill(Color.white.opacity(isSelected ? GlassToken.fillActive : 0))
        }
        .contentShape(Rectangle())
    }
}
