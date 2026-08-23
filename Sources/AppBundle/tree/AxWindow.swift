import AppKit

final class AxWindow {
    let windowId: UInt32
    let ax: AXUIElement
    private let axSubscriptions: [AxSubscription]

    private init(windowId: UInt32, _ ax: AXUIElement, _ axSubscriptions: [AxSubscription]) {
        self.windowId = windowId
        self.ax = ax
        assert(!axSubscriptions.isEmpty)
        self.axSubscriptions = axSubscriptions
    }

    static func new(windowId: UInt32, _ ax: AXUIElement, _ nsApp: NSRunningApplication, _ job: RunLoopJob) throws -> AxWindow? {
        // The 1s messaging-timeout cap set on the app element does not extend to window
        // elements — they'd use the 6s global default, so one CPU-starved app with N windows
        // could stall its AX thread for 6×N seconds per refresh.
        AXUIElementSetMessagingTimeout(ax, 1.0)
        let handlers: HandlerToNotifKeyMapping = [
            (refreshObs, [kAXUIElementDestroyedNotification, kAXWindowDeminiaturizedNotification, kAXWindowMiniaturizedNotification]),
            (movedObs, [kAXMovedNotification]),
            (resizedObs, [kAXResizedNotification]),
        ]
        let subscriptions = try AxSubscription.bulkSubscribe(nsApp, ax, job, handlers)
        return !subscriptions.isEmpty ? AxWindow(windowId: windowId, ax, subscriptions) : nil
    }
}
