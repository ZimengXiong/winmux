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

    init(model: WindowTabDropPreviewViewModel) {
        title = model.title
        subtitle = model.subtitle
        style = model.style
    }
}

struct WindowTabDropPreviewViewModel: Equatable {
    let frame: CGRect
    let title: String
    let subtitle: String
    let style: WindowTabDropPreviewStyle
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
        return
    }
    _ = updatePendingDetachedTabIntent(sourceWindow: window, mouseLocation: mouseLocation, origin: .tabStrip)
}

@MainActor
private func updateMoveFromTabStrip(_ windowId: UInt32) {
    guard let window = Window.get(byId: windowId) else {
        clearPendingWindowDragIntent()
        return
    }
    currentlyManipulatedWithMouseWindowId = window.windowId
    WindowTabStripPanelController.shared.setIgnoresMouseEvents(true)
    _ = updatePendingWindowDragIntent(sourceWindow: window, mouseLocation: mouseLocation)
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
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color(nsColor: .underPageBackgroundColor),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.72), lineWidth: 1.5)
                }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.16))
                        .frame(width: 42, height: 14)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 54, height: 16)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.16))
                        .frame(width: 34, height: 14)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(model.subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.72))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .scaleEffect(isPresented ? 1 : 0.97)
        .opacity(1)
        .shadow(color: Color.accentColor.opacity(0.18), radius: 12, y: 4)
    }

    private func genericPreview(accent: Color, dash: [CGFloat]) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: dash))
                }

            VStack(spacing: 3) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(model.subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.14), radius: 12, y: 6),
            )
            .scaleEffect(isPresented ? 1 : 0.96)
            .opacity(1)
        }
    }

    private var sidebarWorkspaceMovePreview: some View {
        let iconName = model.title.hasPrefix("Tab Group") ? "square.stack.3d.up.fill" : "macwindow"
        return HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 24, height: 18)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                    .frame(width: 24, height: 18)
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(model.subtitle)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6),
        )
        .scaleEffect(isPresented ? 1 : 0.94)
        .opacity(1)
    }
}
