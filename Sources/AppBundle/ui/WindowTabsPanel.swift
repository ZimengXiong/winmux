import AppKit
import SwiftUI

private let windowTabStripPanelPrefix = "AeroSpace.windowTabs.strip."
private let windowTabDropPreviewPanelId = "AeroSpace.windowTabs.dropPreview"
private let windowDragCursorProxyPanelId = "AeroSpace.windowTabs.cursorProxy"

@MainActor
final class WindowTabStripPanelController {
    static let shared = WindowTabStripPanelController()

    private var panels: [ObjectIdentifier: WindowTabStripPanel] = [:]

    private init() {}

    func refresh() {
        guard TrayMenuModel.shared.isEnabled, config.windowTabs.enabled else {
            hideAll()
            return
        }

        let strips = TrayMenuModel.shared.windowTabStrips
        let activeIds = Set(strips.map(\.id))
        for strip in strips {
            let panel = panels[strip.id] ?? WindowTabStripPanel(id: strip.id)
            panels[strip.id] = panel
            panel.update(with: strip)
        }
        for staleId in panels.keys where !activeIds.contains(staleId) {
            panels[staleId]?.orderOut(nil)
            panels.removeValue(forKey: staleId)
        }
    }

    func hideAll() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    func setIgnoresMouseEvents(_ ignoresMouseEvents: Bool) {
        for panel in panels.values {
            panel.ignoresMouseEvents = ignoresMouseEvents
        }
    }
}

@MainActor
private final class WindowTabStripPanel: NSPanelHud {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var currentContent: WindowTabStripContent? = nil

    init(id: ObjectIdentifier) {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowTabStripPanelPrefix + String(id.hashValue))
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = .clear
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func update(with strip: WindowTabStripViewModel) {
        let nextContent = WindowTabStripContent(strip: strip)
        if currentContent != nextContent {
            hostingView.rootView = AnyView(WindowTabStripView(strip: strip))
            currentContent = nextContent
        }
        setFrame(strip.frame, display: true, animate: false)
        ignoresMouseEvents = currentlyManipulatedWithMouseWindowId != nil
        orderFrontRegardless()
    }
}

private struct WindowTabStripContent: Equatable {
    let workspaceName: String
    let tabs: [WindowTabItemViewModel]

    init(strip: WindowTabStripViewModel) {
        workspaceName = strip.workspaceName
        tabs = strip.tabs
    }
}

@MainActor
final class WindowTabDropPreviewPanel: NSPanelHud {
    static let shared = WindowTabDropPreviewPanel()

    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var currentContent: WindowTabDropPreviewContent? = nil

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowTabDropPreviewPanelId)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func show(_ preview: WindowTabDropPreviewViewModel) {
        let nextContent = WindowTabDropPreviewContent(model: preview)
        if currentContent != nextContent {
            hostingView.rootView = AnyView(WindowTabDropPreviewView(model: preview))
            currentContent = nextContent
        }
        setFrame(preview.frame, display: true, animate: false)
        orderFrontRegardless()
    }

    func hide() {
        currentContent = nil
        orderOut(nil)
    }
}

// MARK: - Cursor Drag Proxy (follows cursor during sidebar-originated drags)

@MainActor
final class WindowDragCursorProxyPanel: NSPanelHud {
    static let shared = WindowDragCursorProxyPanel()

    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var currentLabel: String? = nil

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowDragCursorProxyPanelId)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func show(label: String, isGroup: Bool, mouseScreenPoint: CGPoint) {
        if currentLabel != label {
            hostingView.rootView = AnyView(WindowDragCursorProxyView(label: label, isGroup: isGroup))
            currentLabel = label
        }
        let proxyWidth: CGFloat = min(max(CGFloat(label.count) * 7 + 36, 80), 200)
        let proxyHeight: CGFloat = 28
        // Offset: slightly below and to the right of the cursor
        let frame = CGRect(
            x: mouseScreenPoint.x + 14,
            y: mouseScreenPoint.y - proxyHeight - 6,
            width: proxyWidth,
            height: proxyHeight,
        )
        setFrame(frame, display: true, animate: false)
        orderFrontRegardless()
    }

    func hide() {
        currentLabel = nil
        orderOut(nil)
    }
}

private struct WindowDragCursorProxyView: View {
    let label: String
    let isGroup: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isGroup ? "square.stack" : "macwindow")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
        )
    }
}

private struct WindowTabDropPreviewContent: Equatable {
    let title: String
    let subtitle: String
    let style: WindowTabDropPreviewStyle
    let isGroup: Bool

    init(model: WindowTabDropPreviewViewModel) {
        title = model.title
        subtitle = model.subtitle
        style = model.style
        isGroup = model.isGroup
    }
}

struct WindowTabDropPreviewViewModel: Equatable {
    let frame: CGRect
    let title: String
    let subtitle: String
    let style: WindowTabDropPreviewStyle
    let isGroup: Bool
}

enum WindowTabDropPreviewStyle: Equatable {
    case tabInsert
    case detach
    case swap
    case workspaceMove
    case sidebarWorkspaceMove
}

@MainActor
private func focusWindowFromTabStrip(_ windowId: UInt32, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId) else {
                _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
                return
            }
            _ = window.focusWindow()
            window.nativeFocus()
        }
    }
}

@MainActor
private func removeWindowFromTabStrip(_ windowId: UInt32, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId) else {
                _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
                return
            }
            _ = removeWindowFromTabStack(window)
            window.nativeFocus()
        }
    }
}

@MainActor
private func updateDetachedTabFromTabStrip(_ windowId: UInt32) {
    guard let window = Window.get(byId: windowId) else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    _ = beginWindowMoveWithMouseSessionIfNeeded(
        windowId: window.windowId,
        subject: .window,
        detachOrigin: .tabStrip,
        startedInSidebar: false,
        anchorRect: resolvedDraggedWindowAnchorRect(for: window, subject: .window),
    )
    _ = updatePendingDetachedTabIntent(sourceWindow: window, mouseLocation: mouseLocation, origin: .tabStrip)
}

@MainActor
func shouldDeferWindowTabStripGroupDragToDetachedTabDrag() -> Bool {
    getCurrentMouseManipulationKind() == .move &&
        getCurrentMouseDragSubject() == .window &&
        getCurrentMouseTabDetachOrigin() == .tabStrip
}

func isWindowTabStripDragInProgress(
    kind: MouseManipulationKind,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    startedInSidebar: Bool,
) -> Bool {
    guard kind == .move, !startedInSidebar else { return false }
    return detachOrigin == .tabStrip || subject == .group
}

@MainActor
func isWindowTabStripDragInProgress() -> Bool {
    isWindowTabStripDragInProgress(
        kind: getCurrentMouseManipulationKind(),
        subject: getCurrentMouseDragSubject(),
        detachOrigin: getCurrentMouseTabDetachOrigin(),
        startedInSidebar: getCurrentMouseDragStartedInSidebar(),
    )
}

@MainActor
func shouldHandleWindowTabStripGroupDragEnd() -> Bool {
    !shouldDeferWindowTabStripGroupDragToDetachedTabDrag()
}

@MainActor
private func updateMoveFromTabStrip(_ windowId: UInt32) {
    guard let window = Window.get(byId: windowId) else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    if shouldDeferWindowTabStripGroupDragToDetachedTabDrag() {
        return
    }
    _ = beginWindowMoveWithMouseSessionIfNeeded(
        windowId: window.windowId,
        subject: .group,
        detachOrigin: .window,
        startedInSidebar: false,
        anchorRect: resolvedDraggedWindowAnchorRect(for: window, subject: .group),
    )
    _ = updatePendingWindowDragIntent(sourceWindow: window, mouseLocation: mouseLocation, subject: .group, detachOrigin: .window)
}

@MainActor
private func finishMoveFromTabStrip() {
    guard shouldHandleWindowTabStripGroupDragEnd() else { return }
    Task { @MainActor in
        try? await resetManipulatedWithMouseIfPossible()
    }
}

// MARK: - Constants

private let windowTabStripCornerRadius: CGFloat = 14
private let windowTabItemCornerRadius: CGFloat = 10
private let windowTabPreviewCornerRadius: CGFloat = 6

// MARK: - Tab Strip View

private struct WindowTabStripView: View {
    let strip: WindowTabStripViewModel

    var body: some View {
        let count = max(strip.tabs.count, 1)
        let tabWidth = max(100, min(220, (strip.frame.width - 12) / CGFloat(count)))

        HStack(spacing: 2) {
            ForEach(strip.tabs) { tab in
                WindowTabItemView(
                    tab: tab,
                    width: tabWidth,
                    height: max(strip.frame.height - 6, 22)
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: windowTabStripCornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: windowTabStripCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { _ in
                    if let activeTab = strip.tabs.first(where: \.isActive) ?? strip.tabs.first {
                        updateMoveFromTabStrip(activeTab.windowId)
                    }
                }
                .onEnded { _ in
                    finishMoveFromTabStrip()
                },
        )
    }
}

// MARK: - Tab Item View (hover animations)

private struct WindowTabItemView: View {
    let tab: WindowTabItemViewModel
    let width: CGFloat
    let height: CGFloat

    @State private var isHovered = false

    var body: some View {
        Button {
            guard !isWindowTabStripDragInProgress() else { return }
            focusWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
        } label: {
            Text(tab.title)
                .font(.system(size: 11, weight: tab.isActive ? .medium : .regular))
                .lineLimit(1)
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(width: width, height: height)
                .background(background)
        }
        .contentShape(RoundedRectangle(cornerRadius: windowTabItemCornerRadius, style: .continuous))
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Remove Tab From Stack") {
                removeWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { _ in
                    updateDetachedTabFromTabStrip(tab.windowId)
                }
                .onEnded { _ in
                    Task { @MainActor in
                        try? await resetManipulatedWithMouseIfPossible()
                    }
                },
        )
    }

    private var foregroundColor: Color {
        if tab.isActive {
            return Color.primary
        }
        return isHovered ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.65)
    }

    @ViewBuilder
    private var background: some View {
        if tab.isActive {
            RoundedRectangle(cornerRadius: windowTabItemCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: windowTabItemCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                }
        } else if isHovered {
            RoundedRectangle(cornerRadius: windowTabItemCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }
}

// MARK: - Drop Preview (visible fill + border)

private struct WindowTabDropPreviewView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: WindowTabDropPreviewViewModel
    @State private var isPresented = false

    var body: some View {
        let cfg = borderConfig(for: model.style)

        RoundedRectangle(cornerRadius: windowTabPreviewCornerRadius, style: .continuous)
            .fill(cfg.color.opacity(isPresented ? cfg.fillOpacity : 0))
            .overlay {
                RoundedRectangle(cornerRadius: windowTabPreviewCornerRadius, style: .continuous)
                    .strokeBorder(
                        cfg.color.opacity(isPresented ? cfg.borderOpacity : 0.1),
                        style: cfg.strokeStyle
                    )
            }
            .scaleEffect(reduceMotion ? 1 : (isPresented ? 1 : 0.996))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.18, dampingFraction: 0.82)) {
                    isPresented = true
                }
            }
    }

    private struct BorderConfig {
        let color: Color
        let fillOpacity: Double
        let borderOpacity: Double
        let strokeStyle: StrokeStyle
    }

    private func borderConfig(for style: WindowTabDropPreviewStyle) -> BorderConfig {
        switch style {
            case .tabInsert:
                // Solid accent, visible fill — "join this tab group"
                return BorderConfig(color: .accentColor, fillOpacity: 0.08, borderOpacity: 0.7, strokeStyle: StrokeStyle(lineWidth: 2.5))
            case .detach:
                // Orange dashed, light fill — "pulling out of group"
                return BorderConfig(color: .orange, fillOpacity: 0.06, borderOpacity: 0.6, strokeStyle: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            case .swap:
                // Accent dashed, visible fill — "swap positions"
                return BorderConfig(color: .accentColor, fillOpacity: 0.06, borderOpacity: 0.55, strokeStyle: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            case .workspaceMove:
                // Green, visible fill — "move to workspace"
                return BorderConfig(color: .green, fillOpacity: 0.07, borderOpacity: 0.6, strokeStyle: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            case .sidebarWorkspaceMove:
                // Accent solid — sidebar drop target
                return BorderConfig(color: .accentColor, fillOpacity: 0.06, borderOpacity: 0.6, strokeStyle: StrokeStyle(lineWidth: 2))
        }
    }
}
