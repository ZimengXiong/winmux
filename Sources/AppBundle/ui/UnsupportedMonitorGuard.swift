import AppKit
import CoreGraphics
import SwiftUI

private let unsupportedMonitorPanelPrefix = "WinMux.unsupportedMonitor."

private struct UnsupportedMonitorView: View {
    let onAllowUnmanaged: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Text(
                    """
                    WinMux only supports one managed monitor at this time.
                    Configure the main monitor in Settings > Displays > Use As > Main Display,
                    or use this display unmanaged.
                    """
                )
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.65)

                Button(action: onAllowUnmanaged) {
                    Text("Use This Monitor Unmanaged")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

@MainActor
private final class UnsupportedMonitorPanel: NSPanelHud {
    private let hostingView: NSHostingView<UnsupportedMonitorView>

    init(id: String, onAllowUnmanaged: @escaping () -> Void) {
        hostingView = NSHostingView(rootView: UnsupportedMonitorView(onAllowUnmanaged: onAllowUnmanaged))
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

    override var canBecomeKey: Bool { true }
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
    private var unmanagedMonitorIds: Set<String> = []

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

    func shouldManageWindow(at point: CGPoint) -> Bool {
        unmanagedMonitor(containing: point) == nil
    }

    private func handleScreenParametersChanged() {
        refreshMonitorPolicy(refreshReason: NSApplication.didChangeScreenParametersNotification.rawValue)
    }

    private func allowMonitorUnmanaged(id: String) {
        guard unmanagedMonitorIds.insert(id).inserted else { return }
        refreshMonitorPolicy(refreshReason: "UnsupportedMonitorGuard.allowMonitorUnmanaged")
    }

    private func refreshMonitorPolicy(refreshReason: String) {
        refreshPanels()
        WorkspaceSidebarPanel.shared.refresh()
        WindowTabStripPanelController.shared.refresh()
        if TrayMenuModel.shared.isEnabled {
            scheduleRefreshSession(.globalObserver(refreshReason))
        }
    }

    private func refreshPanels() {
        let unsupportedScreens = unsupportedScreens().filter { !unmanagedMonitorIds.contains($0.id) }
        guard !unsupportedScreens.isEmpty else {
            hideAll()
            return
        }

        let activePanelIds = Set(
            unsupportedScreens.map(\.id)
        )
        for unsupportedScreen in unsupportedScreens {
            let id = unsupportedScreen.id
            let screen = unsupportedScreen.screen
            let panel = panels[id] ?? UnsupportedMonitorPanel(id: id) {
                UnsupportedMonitorGuard.shared.allowMonitorUnmanaged(id: id)
            }
            panels[id] = panel
            panel.update(screen: screen)
        }
        for id in panels.keys where !activePanelIds.contains(id) {
            panels[id]?.orderOut(nil)
            panels.removeValue(forKey: id)
        }
    }

    private func unsupportedScreens() -> [(id: String, screen: NSScreen)] {
        NSScreen.screens.enumerated()
            .filter { $0.element.displayId != CGMainDisplayID() }
            .map { (panelId(index: $0.offset, screen: $0.element), $0.element) }
    }

    private func unmanagedMonitor(containing point: CGPoint) -> NSScreen? {
        unsupportedScreens()
            .first {
                unmanagedMonitorIds.contains($0.id) &&
                    $0.screen.frame.monitorFrameNormalized().contains(point)
            }?
            .screen
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

@MainActor
func shouldWinMuxManageWindow(at point: CGPoint) -> Bool {
    UnsupportedMonitorGuard.shared.shouldManageWindow(at: point)
}
