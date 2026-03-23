import AppKit
import SwiftUI

private let windowTabStripPanelPrefix = "AeroSpace.windowTabs.strip."
private let windowTabDropPreviewPanelId = "AeroSpace.windowTabs.dropPreview"

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
                _ = Workspace.get(byName: fallbackWorkspace).focusWorkspace()
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
                _ = Workspace.get(byName: fallbackWorkspace).focusWorkspace()
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
    currentlyManipulatedWithMouseWindowId = window.windowId
    setCurrentMouseManipulationKind(.move)
    setCurrentMouseDragSubject(.window)
    setCurrentMouseTabDetachOrigin(.tabStrip)
    setCurrentMouseDragStartedInSidebar(false)
    setDraggedWindowAnchorRect(resolvedDraggedWindowAnchorRect(for: window, subject: .window), for: window.windowId)
    WindowTabStripPanelController.shared.setIgnoresMouseEvents(true)
    _ = updatePendingDetachedTabIntent(sourceWindow: window, mouseLocation: mouseLocation, origin: .tabStrip)
}

@MainActor
private func updateMoveFromTabStrip(_ windowId: UInt32) {
    guard let window = Window.get(byId: windowId) else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    if getCurrentMouseManipulationKind() == .move &&
        currentlyManipulatedWithMouseWindowId != nil &&
        getCurrentMouseDragSubject() == .window
    {
        return
    }
    currentlyManipulatedWithMouseWindowId = window.windowId
    setCurrentMouseManipulationKind(.move)
    setCurrentMouseDragSubject(.group)
    setCurrentMouseTabDetachOrigin(.window)
    setCurrentMouseDragStartedInSidebar(false)
    setDraggedWindowAnchorRect(resolvedDraggedWindowAnchorRect(for: window, subject: .group), for: window.windowId)
    WindowTabStripPanelController.shared.setIgnoresMouseEvents(true)
    _ = updatePendingWindowDragIntent(sourceWindow: window, mouseLocation: mouseLocation, subject: .group, detachOrigin: .window)
}

@MainActor
private func finishMoveFromTabStrip() {
    Task { @MainActor in
        try? await resetManipulatedWithMouseIfPossible()
    }
}

private struct WindowTabStripView: View {
    let strip: WindowTabStripViewModel

    var body: some View {
        let count = max(strip.tabs.count, 1)
        let tabWidth = max(128, min(220, (strip.frame.width - 10) / CGFloat(count)))
        let activeTab = strip.tabs.first(where: \.isActive) ?? strip.tabs.first

        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor).opacity(0.96),
                            Color(nsColor: .underPageBackgroundColor).opacity(0.9),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { _ in
                            if let activeTab {
                                updateMoveFromTabStrip(activeTab.windowId)
                            }
                        },
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onEnded { _ in
                            finishMoveFromTabStrip()
                        },
                )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(strip.tabs) { tab in
                        WindowTabItemView(tab: tab, width: tabWidth, height: max(strip.frame.height - 4, 24))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

private struct WindowTabDropPreviewChrome: View {
    let title: String
    let subtitle: String
    let accent: Color
    let badgeText: String
    let isPresented: Bool
    let borderStyle: StrokeStyle

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 180 || geometry.size.height < 52
            let isUltraCompact = geometry.size.width < 132 || geometry.size.height < 40

            HStack(spacing: isCompact ? 8 : 12) {
                Capsule(style: .continuous)
                    .fill(accent.opacity(0.8))
                    .frame(width: 4, height: isCompact ? 22 : 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: isCompact ? 11 : 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if !isUltraCompact {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 0)

                if !isCompact {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(accent.opacity(0.92))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(accent.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, isCompact ? 10 : 12)
            .padding(.vertical, isCompact ? 7 : 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.28), style: borderStyle)
                }
        )
        .scaleEffect(isPresented ? 1 : 0.96)
        .opacity(isPresented ? 1 : 0.92)
        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
    }
}

private struct WindowTabItemView: View {
    let tab: WindowTabItemViewModel
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Button {
            focusWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
        } label: {
            HStack(spacing: 8) {
                Capsule(style: .continuous)
                    .fill(tab.isActive ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 20)
                Text(tab.title)
                    .font(.system(size: 12, weight: tab.isActive ? .semibold : .medium, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(tab.isActive ? Color.primary : Color.primary.opacity(0.72))
            }
            .padding(.horizontal, 12)
            .frame(width: width, height: height, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tab.isActive ? Color.primary.opacity(0.08) : Color.clear),
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(tab.isActive ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove Tab From Stack") {
                removeWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
            }
        }
        .simultaneousGesture(
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
}

private struct WindowTabDropPreviewView: View {
    let model: WindowTabDropPreviewViewModel
    @State private var isPresented = false

    var body: some View {
        Group {
            switch model.style {
                case .tabInsert:
                    tabInsertPreview
                case .detach:
                    genericPreview(accent: Color.orange, dash: [7, 5])
                case .swap:
                    genericPreview(accent: Color.accentColor, dash: [7, 5])
                case .workspaceMove:
                    genericPreview(accent: Color.green.opacity(0.85), dash: [7, 5])
                case .sidebarWorkspaceMove:
                    sidebarWorkspaceMovePreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                isPresented = true
            }
        }
    }

    private var tabInsertPreview: some View {
        WindowTabDropPreviewChrome(
            title: model.title,
            subtitle: model.subtitle,
            accent: Color.accentColor,
            badgeText: "Tabs",
            isPresented: isPresented,
            borderStyle: StrokeStyle(lineWidth: 1.5),
        )
    }

    private func genericPreview(accent: Color, dash: [CGFloat]) -> some View {
        let badgeText: String = switch model.style {
            case .detach: "Detach"
            case .swap: "Swap"
            case .workspaceMove: "Move"
            case .sidebarWorkspaceMove: "Move"
            case .tabInsert: "Tabs"
        }
        return WindowTabDropPreviewChrome(
            title: model.title,
            subtitle: model.subtitle,
            accent: accent,
            badgeText: badgeText,
            isPresented: isPresented,
            borderStyle: StrokeStyle(lineWidth: 1.5, dash: dash),
        )
    }

    private var sidebarWorkspaceMovePreview: some View {
        WindowTabDropPreviewChrome(
            title: model.title,
            subtitle: model.subtitle,
            accent: Color.accentColor,
            badgeText: "Sidebar",
            isPresented: isPresented,
            borderStyle: StrokeStyle(lineWidth: 1),
        )
    }
}
