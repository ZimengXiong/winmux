import AppKit

@MainActor
final class MonitorConfigurationObserver {
    static let shared = MonitorConfigurationObserver()

    private var observer: NSObjectProtocol?
    private var screenChangeGeneration: UInt64 = 0

    private init() {}

    func prepareForStartup() {
        refreshMonitorPolicy(refreshReason: "MonitorConfigurationObserver.prepareForStartup")
    }

    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
        ) { _ in
            Task { @MainActor in
                MonitorConfigurationObserver.shared.handleScreenParametersChanged()
            }
        }
    }

    private func handleScreenParametersChanged() {
        refreshMonitorPolicy(refreshReason: NSApplication.didChangeScreenParametersNotification.rawValue)
        scheduleSettledRefresh()
    }

    private func refreshMonitorPolicy(refreshReason: String) {
        WorkspaceSidebarPanel.refreshAll()
        WindowTabStripPanelController.shared.refresh()
        if TrayMenuModel.shared.isEnabled {
            scheduleRefreshSession(.globalObserver(refreshReason))
        }
    }

    private func scheduleSettledRefresh() {
        screenChangeGeneration += 1
        let generation = screenChangeGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard generation == screenChangeGeneration else { return }
            refreshMonitorPolicy(refreshReason: "\(NSApplication.didChangeScreenParametersNotification.rawValue).settled")
        }
    }
}
