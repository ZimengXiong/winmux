import AppKit

@MainActor
final class UnsupportedMonitorGuard {
    static let shared = UnsupportedMonitorGuard()

    private var observer: NSObjectProtocol?

    private init() {}

    func prepareForStartup() {
        refreshMonitorPolicy(refreshReason: "UnsupportedMonitorGuard.prepareForStartup")
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

    func shouldManageWindow(at _: CGPoint) -> Bool {
        true
    }

    private func handleScreenParametersChanged() {
        refreshMonitorPolicy(refreshReason: NSApplication.didChangeScreenParametersNotification.rawValue)
    }

    private func refreshMonitorPolicy(refreshReason: String) {
        WorkspaceSidebarPanel.shared.refresh()
        WindowTabStripPanelController.shared.refresh()
        if TrayMenuModel.shared.isEnabled {
            scheduleRefreshSession(.globalObserver(refreshReason))
        }
    }
}

@MainActor
func shouldWinMuxManageWindow(at point: CGPoint) -> Bool {
    UnsupportedMonitorGuard.shared.shouldManageWindow(at: point)
}
