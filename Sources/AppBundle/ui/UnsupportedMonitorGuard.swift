import AppKit
import CoreGraphics
import SwiftUI

private let unsupportedMonitorPanelPrefix = "AeroSpace.unsupportedMonitor."

private struct UnsupportedMonitorView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Text("WinMux only supports one monitor at this time.\nConfigure main monitor in Settings > Displays > Use As > Main Display.")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.65)
                .padding(48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private final class UnsupportedMonitorPanel: NSPanelHud {
    private let hostingView = NSHostingView(rootView: UnsupportedMonitorView())

    init(id: String) {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(unsupportedMonitorPanelPrefix + id)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = .black
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(screen: NSScreen) {
        let screenFrame = screen.frame
        if frame != screenFrame {
            setFrame(screenFrame, display: true, animate: false)
        }
        orderFrontRegardless()
    }
}

@MainActor
final class UnsupportedMonitorGuard {
    static let shared = UnsupportedMonitorGuard()

    private var observer: NSObjectProtocol?
    private var panels: [String: UnsupportedMonitorPanel] = [:]

    private init() {}

    func prepareForStartup() {
        refreshPanels()
    }

    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
        ) { _ in
            Task { @MainActor in
                UnsupportedMonitorGuard.shared.handleScreenParametersChanged()
            }
        }
    }

    private func handleScreenParametersChanged() {
        refreshPanels()
        WorkspaceSidebarPanel.shared.refresh()
        WindowTabStripPanelController.shared.refresh()
        if TrayMenuModel.shared.isEnabled {
            scheduleRefreshSession(.globalObserver(NSApplication.didChangeScreenParametersNotification.rawValue))
        }
    }

    private func refreshPanels() {
        let unsupportedScreens = NSScreen.screens.enumerated().filter { $0.element.displayId != CGMainDisplayID() }
        guard !unsupportedScreens.isEmpty else {
            hideAll()
            return
        }

        let activePanelIds = Set(
            unsupportedScreens.map { panelId(index: $0.offset, screen: $0.element) }
        )
        for (index, screen) in unsupportedScreens {
            let id = panelId(index: index, screen: screen)
            let panel = panels[id] ?? UnsupportedMonitorPanel(id: id)
            panels[id] = panel
            panel.update(screen: screen)
        }
        for id in panels.keys where !activePanelIds.contains(id) {
            panels[id]?.orderOut(nil)
            panels.removeValue(forKey: id)
        }
    }

    private func panelId(index: Int, screen: NSScreen) -> String {
        screen.displayId.map(String.init) ?? "screen-\(index)"
    }

    private func hideAll() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }
}
