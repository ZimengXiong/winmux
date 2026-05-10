import AppKit
import Common
import SwiftUI

private let exposePanelId = "WinMux.expose"

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

extension ExposeWindowItem {
    func withThumbnail(_ thumbnail: NSImage?) -> ExposeWindowItem {
        guard let thumbnail else { return self }
        return ExposeWindowItem(
            id: id,
            title: title,
            appName: appName,
            thumbnail: thumbnail,
            aspectRatio: aspectRatio,
            isFocused: isFocused,
            widthRatio: widthRatio,
        )
    }
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
        applyWinMuxLayer(.overlay)
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
            if c.layout == .tabGroup, c.children.count > 1 {
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
    let ar: CGFloat = w.lastAppliedLayoutPhysicalRect.map { $0.width / $0.height } ?? 1.5
    let wr: CGFloat = w.lastAppliedLayoutPhysicalRect.map { $0.width / max(1, screenWidth) } ?? 1.0
    return ExposeWindowItem(id: w.windowId, title: sidebarDisplayLabel(for: w),
                            appName: w.app.name ?? "Unknown", thumbnail: nil,
                            aspectRatio: ar, isFocused: w.windowId == focusedWindowId,
                            widthRatio: wr)
}
