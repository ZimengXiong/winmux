import AppKit
import Common

// Potential alternative implementation
// https://github.com/swiftlang/swift-evolution/blob/main/proposals/0392-custom-actor-executors.md
// (only available since macOS 14)
final class MacApp: AbstractApp {
    /*conforms*/ let pid: Int32
    /*conforms*/ let rawAppBundleId: String?
    let appId: KnownBundleId?
    let nsApp: NSRunningApplication
    private let axApp: ThreadGuardedValue<AXUIElement>
    /// Second app element with a much shorter messaging timeout, for the focused-window query
    /// that fronts every refresh session: when the app is too busy to answer quickly, the
    /// session must fall back to the event-maintained cache instead of stalling on the full
    /// timeout (and then acting as if no window were focused at all).
    private let axAppFastTimeout: ThreadGuardedValue<AXUIElement>
    private let appAxSubscriptions: ThreadGuardedValue<[AxSubscription]> // keep subscriptions in memory
    private let windows: ThreadGuardedValue<[UInt32: AxWindow]> = .init([:])
    private var windowsCount = 0
    var lastNativeFocusedWindowId: UInt32? = nil
    private var thread: Thread?
    private var setFrameJobs: [UInt32: RunLoopJob] = [:]
    @MainActor private static var focusJob: RunLoopJob? = nil

    /*conforms*/ var name: String? { nsApp.localizedName }
    /*conforms*/ var execPath: String? { nsApp.executableURL?.path }
    /*conforms*/ var bundlePath: String? { nsApp.bundleURL?.path }

    // todo think if it's possible to integrate this global mutable state to https://github.com/nikitabobko/WinMux/issues/1215
    //      and make deinitialization automatic in deinit
    @MainActor static var allAppsMap: [pid_t: MacApp] = [:]
    @MainActor private static var wipPids: [pid_t: AwaitableOneTimeBroadcastLatch] = [:]

    private init(_ nsApp: NSRunningApplication, _ axApp: AXUIElement, _ axAppFastTimeout: AXUIElement, _ axSubscriptions: [AxSubscription], _ thread: Thread) {
        self.nsApp = nsApp
        self.axApp = .init(axApp)
        self.axAppFastTimeout = .init(axAppFastTimeout)
        self.pid = nsApp.processIdentifier
        self.rawAppBundleId = nsApp.bundleIdentifier
        self.appId = nsApp.bundleIdentifier.flatMap { KnownBundleId.init(rawValue: $0) }
        assert(!axSubscriptions.isEmpty)
        self.appAxSubscriptions = .init(axSubscriptions)
        self.thread = thread
    }

    @MainActor
    @discardableResult
    static func getOrRegister(_ nsApp: NSRunningApplication) async throws -> MacApp? {
        // Don't perceive any of the lock screen windows as real windows
        // Otherwise, false positive ax notifications might trigger that lead to gcWindows
        if nsApp.bundleIdentifier == lockScreenAppBundleId { return nil }
        let pid = nsApp.processIdentifier
        // AX requests crash if you send them to yourself
        if pid == myPid { return nil }

        var attempted = false
        while true {
            if let existing = allAppsMap[pid] { return existing }
            try checkCancellation()
            if let wip = wipPids[pid] {
                try await wip.await()
                continue
            }
            // Registration can fail (app still launching, AX subscription rejected). In that case
            // allAppsMap[pid] stays absent, so without this guard the loop would respawn the
            // registration thread forever, stalling every refresh that awaits this app.
            if attempted { return nil }
            attempted = true
            let wip = AwaitableOneTimeBroadcastLatch()
            wipPids[pid] = wip

            let thread = Thread {
                $axTaskLocalAppThreadToken.withValue(AxAppThreadToken(pid: pid, idForDebug: nsApp.idForDebug)) {
                    let axApp = AXUIElementCreateApplication(nsApp.processIdentifier)
                    // Cap AX round-trips to this app at 1s instead of the 6s global default,
                    // so a busy/unresponsive app can't stall window operations for seconds.
                    AXUIElementSetMessagingTimeout(axApp, 1.0)
                    let axAppFastTimeout = AXUIElementCreateApplication(nsApp.processIdentifier)
                    AXUIElementSetMessagingTimeout(axAppFastTimeout, MacApp.focusedWindowQueryTimeout)
                    let handlers: HandlerToNotifKeyMapping = [
                        (refreshObs, [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]),
                    ]
                    let job = RunLoopJob()
                    let subscriptions = (try? AxSubscription.bulkSubscribe(nsApp, axApp, job, handlers)) ?? []
                    let isGood = !subscriptions.isEmpty
                    let app = isGood ? MacApp(nsApp, axApp, axAppFastTimeout, subscriptions, Thread.current) : nil
                    Task { @MainActor in
                        allAppsMap[pid] = app
                        await wip.signalToAll()
                        wipPids[pid] = nil
                    }
                    if isGood {
                        CFRunLoopRun()
                    }
                }
            }
            thread.name = "AxAppThread \(nsApp.idForDebug)"
            thread.start()
        }
    }

    func closeAndUnregisterAxWindow(_ windowId: UInt32) {
        if serverArgs.isReadOnly { return }
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        _ = withWindowAsync(windowId) { [windows] window, job in
            guard let closeButton = window.get(Ax.closeButtonAttr) else { return }
            if AXUIElementPerformAction(closeButton.cast, kAXPressAction as CFString) == .success {
                windows.threadGuarded.removeValue(forKey: windowId)
            }
        }
    }

    func pressCloseButton(_ windowId: UInt32) async throws -> Bool {
        if serverArgs.isReadOnly { return false }
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        return try await withWindow(windowId) { window, job in
            guard let closeButton = window.get(Ax.closeButtonAttr) else { return false }
            return AXUIElementPerformAction(closeButton.cast, kAXPressAction as CFString) == .success
        } ?? false
    }

    func containsAxWindow(_ windowId: UInt32) async throws -> Bool {
        try await thread?.runInLoop { [axApp] job in
            axApp.threadGuarded.get(Ax.windowsAttr)?.contains { $0.windowId == windowId } ?? false
        } ?? false
    }

    func getAxSize(_ windowId: UInt32) async throws -> CGSize? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.sizeAttr)
        }
    }

    /// How long the focused-window query may block a refresh session. Deliberately much shorter
    /// than the general 1s cap: this query fronts every session (including every hotkey), and
    /// on timeout there is an accurate fallback (see getFocusedWindow).
    static let focusedWindowQueryTimeout: Float = 0.25

    private enum FocusedWindowQuery {
        case window(UInt32)
        case noFocusedWindow
        case timedOut
    }

    private func queryFocusedWindowId() async throws -> FocusedWindowQuery {
        try await thread?.runInLoop { [nsApp, axAppFastTimeout, windows] job -> FocusedWindowQuery in
            var raw: AnyObject?
            let error = AXUIElementCopyAttributeValue(axAppFastTimeout.threadGuarded, kAXFocusedWindowAttribute as CFString, &raw)
            switch error {
                case .success:
                    guard let raw else { return .noFocusedWindow }
                    let element = raw as! AXUIElement
                    // Fresh elements use the 6s global default; bound follow-up traffic like
                    // every other window element.
                    AXUIElementSetMessagingTimeout(element, 1.0)
                    guard let windowId = element.containingWindowId(),
                          let registered = try windows.threadGuarded.getOrRegisterAxWindow(windowId: windowId, element, nsApp, job)
                    else { return .noFocusedWindow }
                    return .window(registered.windowId)
                case .cannotComplete:
                    return .timedOut
                default:
                    return .noFocusedWindow
            }
        } ?? .noFocusedWindow
    }

    // todo merge together with detectNewWindows
    func getFocusedWindow() async throws -> Window? {
        switch try await queryFocusedWindowId() {
            case .window(let windowId):
                return try await MacWindow.getOrRegister(windowId: windowId, macApp: self)
            case .noFocusedWindow:
                return nil
            case .timedOut:
                // The app is too busy to answer AX right now. A stalled app cannot change its
                // own focused window (that requires its main run loop), so the last known
                // value — maintained by kAXFocusedWindowChanged events and every successful
                // session — is still accurate. Using it beats both stalling the session for
                // the full messaging timeout and the old behavior of treating the timeout as
                // "no window is focused".
                return lastNativeFocusedWindow()
        }
    }

    @MainActor
    private func lastNativeFocusedWindow() -> Window? {
        lastNativeFocusedWindowId.flatMap { Window.get(byId: $0) }
    }

    @MainActor func nativeFocus(_ windowId: UInt32) {
        if serverArgs.isReadOnly { return }
        MacApp.focusJob?.cancel()
        // Performance optimization. If possible avoid doing AX requests
        // (important for apps which are slow at responding even such basic AX requests. E.g. Godot)
        // Beware of the macOS bug: https://github.com/nikitabobko/WinMux/issues/101
        let useActivationOnly = (!NSScreen.screensHaveSeparateSpaces || monitors.count == 1) &&
            shouldUseActivationOnlyForNativeFocus(
                targetWindowId: windowId,
                lastNativeFocusedWindowId: lastNativeFocusedWindowId,
                logicalWindowsCount: logicalWindowCount,
            )
        debugFocusLog(
            "MacApp.nativeFocus app=\(nsApp.localizedName ?? rawAppBundleId ?? String(pid)) target=\(windowId) lastNative=\(lastNativeFocusedWindowId?.description ?? "nil") logicalWindowsCount=\(logicalWindowCount) windowsCount=\(windowsCount) strategy=\(useActivationOnly ? "activate" : "ax-focus")"
        )
        if useActivationOnly
        {
            nsApp.activate(options: .activateIgnoringOtherApps)
        } else {
            MacApp.focusJob = withWindowAsync(windowId) { [nsApp, axApp] window, job in
                AXUIElementSetAttributeValue(axApp.threadGuarded, kAXFocusedWindowAttribute as CFString, window)
                // Raise firstly to make sure that by the time we activate the app, the window would be already on top
                window.set(Ax.isMainAttr, true)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                nsApp.activate(options: .activateIgnoringOtherApps)
            }
        }
    }

    func setAxFrame(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { [axApp] window, job in
            try setFrame(window, app: axApp.threadGuarded, topLeft, size, job)
        }
    }

    func setAxFrameBlocking(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?) async throws {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        try await withWindow(windowId) { [axApp] window, job in
            try setFrame(window, app: axApp.threadGuarded, topLeft, size, job)
        }
    }

    func getAxWindowsCount() async throws -> Int? {
        try await thread?.runInLoop { [axApp] job in
            axApp.threadGuarded.get(Ax.windowsAttr)?.count
        }
    }

    @MainActor
    private var logicalWindowCount: Int {
        var result = 0
        for window in MacWindow.allWindows where window.macApp === self {
            result += 1
            if result > 1 {
                return result
            }
        }
        return result
    }

    func getAxRect(_ windowId: UInt32) async throws -> Rect? {
        try await withWindow(windowId) { window, job in
            guard let topLeftCorner = window.get(Ax.topLeftCornerAttr) else { return nil }
            guard let size = window.get(Ax.sizeAttr) else { return nil }
            return Rect(topLeftX: topLeftCorner.x, topLeftY: topLeftCorner.y, width: size.width, height: size.height)
        }
    }

    func isWindowHeuristic(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?) async throws -> Bool {
        return try await withWindow(windowId) { [nsApp, axApp, appId] window, job in
            window.isWindowHeuristic(axApp: axApp.threadGuarded, appId, nsApp.activationPolicy, windowLevel)
        } == true
    }

    func getAxUiElementWindowType(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?) async throws -> AxUiElementWindowType {
        return try await withWindow(windowId) { [nsApp, axApp, appId] window, job in
            window.getWindowType(axApp: axApp.threadGuarded, appId, nsApp.activationPolicy, windowLevel)
        } ?? .window
    }

    func isDialogHeuristic(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?) async throws -> Bool {
        try await withWindow(windowId) { [appId] window, job in
            window.isDialogHeuristic(appId, windowLevel)
        } == true
    }

    func setNativeFullscreen(_ windowId: UInt32, _ value: Bool) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { window, job in
            window.set(Ax.isFullscreenAttr, value)
        }
    }

    func setNativeMinimized(_ windowId: UInt32, _ value: Bool) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { window, job in
            window.set(Ax.minimizedAttr, value)
        }
    }

    func dumpWindowAxInfo(windowId: UInt32) async throws -> [String: Json] {
        try await withWindow(windowId) { window, job in
            dumpAxRecursive(window, .window)
        } ?? [:]
    }

    func dumpAppAxInfo() async throws -> [String: Json] {
        try await thread?.runInLoop { [axApp] job in
            dumpAxRecursive(axApp.threadGuarded, .app)
        } ?? [:]
    }

    func getAxTitle(_ windowId: UInt32) async throws -> String? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.titleAttr)
        }
    }

    func isMacosNativeFullscreen(_ windowId: UInt32) async throws -> Bool? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.isFullscreenAttr)
        }
    }

    func isMacosNativeMinimized(_ windowId: UInt32) async throws -> Bool? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.minimizedAttr)
        }
    }

    /// Upper bound on how long one app may hold up the window-refresh barrier. A CPU-starved
    /// app answers each AX message only at the messaging timeout, so its enumeration can take
    /// (windows × timeout); every other app's layout would wait behind it. On deadline the app
    /// falls back to the model's current windows (equivalent to "nothing changed"), and a later
    /// refresh reconciles once the app responds.
    private static let singleAppRefreshDeadline: Duration = .milliseconds(1500)

    @MainActor
    private static func refreshAppAndGetAliveWindowIdsWithDeadline(
        _ nsApp: NSRunningApplication,
        frontmostAppBundleId: String?,
    ) async throws -> [UInt32] {
        let pid = nsApp.processIdentifier
        let work = Task { @MainActor () -> [UInt32] in
            guard let app = try await MacApp.getOrRegister(nsApp) else { return [] }
            return try await app.refreshAndGetAliveWindowIds(frontmostAppBundleId: frontmostAppBundleId)
        }
        let deadline = Task { @MainActor in
            try? await Task.sleep(for: singleAppRefreshDeadline)
            work.cancel()
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            do {
                return try await work.value
            } catch is CancellationError {
                // Propagate if the whole refresh session was cancelled; otherwise the deadline
                // fired — report the model's current windows for this app as alive.
                try checkCancellation()
                return MacWindow.allWindows.filter { $0.macApp.pid == pid }.map(\.windowId)
            }
        } onCancel: {
            work.cancel()
        }
    }

    @MainActor
    static func refreshAllAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> [MacApp: [UInt32]] {
        for (_, app) in MacApp.allAppsMap { // gc dead apps
            try checkCancellation()
            if app.nsApp.isTerminated {
                await app.destroy()
            }
        }
        return try await withThrowingTaskGroup(of: (pid_t, [UInt32]).self, returning: [MacApp: [UInt32]].self) { group in
            func refreshTheApp(_ nsApp: NSRunningApplication) {
                group.addTask { @Sendable @MainActor in
                    (
                        nsApp.processIdentifier,
                        try await refreshAppAndGetAliveWindowIdsWithDeadline(nsApp, frontmostAppBundleId: frontmostAppBundleId)
                    )
                }
            }
            // Register new apps
            for nsApp in NSWorkspace.shared.runningApplications {
                try checkCancellation()
                if nsApp.activationPolicy == .regular {
                    refreshTheApp(nsApp)
                }
            }
            for (_, app) in MacApp.allAppsMap {
                try checkCancellation()
                // "About this Mac" window, TouchID, and a lot of other utility windows
                // We don't monitor them actively as we do for regular apps, but if a window of one of those utility
                // apps got focused it will end up in allAppsMap
                if app.nsApp.activationPolicy != .regular {
                    refreshTheApp(app.nsApp)
                }
            }
            var result: [MacApp: [UInt32]] = [:]
            for try await (pid, windowIds) in group {
                if let app = MacApp.allAppsMap[pid] {
                    result[app] = windowIds
                }
            }
            return result
        }
    }

    private func refreshAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> [UInt32] {
        if nsApp.isTerminated {
            await destroy()
            return []
        }
        guard let thread else { return [] }
        let (alive, dead) = try await thread.runInLoop { [nsApp, windows, axApp] (job) -> ([UInt32], [UInt32]) in
            var alive: [UInt32: AxWindow] = windows.threadGuarded
            var dead = [UInt32: AxWindow]()
            // Second line of defence against lock screen. See the first line of defence: closedWindowsCache
            // Second and third lines of defence are technically needed only to avoid potential flickering
            if frontmostAppBundleId != lockScreenAppBundleId {
                (alive, dead) = try alive.partition {
                    try job.checkCancellation()
                    let (windowId, error) = $0.value.ax.containingWindowIdWithError()
                    if windowId != nil { return true }
                    // .cannotComplete means the app didn't answer (CPU-starved or briefly
                    // unresponsive), not that the window is gone. Treating it as death made
                    // a busy app's windows get GC'd and later re-detected as new windows
                    // (losing their tree position). Keep them; a later refresh reconciles
                    // once the app responds or terminates.
                    return error == .cannotComplete
                }
            }

            for (id, window) in axApp.threadGuarded.get(Ax.windowsAttr) ?? [] {
                try job.checkCancellation()
                try alive.getOrRegisterAxWindow(windowId: id, window, nsApp, job)
            }

            windows.threadGuarded = alive
            return (Array(alive.keys), Array(dead.keys))
        }
        windowsCount = alive.count
        for windowId in dead {
            setFrameJobs.removeValue(forKey: windowId)?.cancel()
        }
        return alive
    }

    private func destroy() async {
        _ = await Task { @MainActor [pid] in _ = MacApp.allAppsMap.removeValue(forKey: pid) }.result
        for (_, job) in setFrameJobs {
            job.cancel()
        }
        setFrameJobs = [:]
        thread?.runInLoopAsync { [windows, appAxSubscriptions, axApp, axAppFastTimeout] job in
            appAxSubscriptions.destroy() // Destroy AX objects in reverse order of their creation
            windows.destroy()
            axAppFastTimeout.destroy()
            axApp.destroy()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        thread = nil // Disallow all future job submissions
    }

    private func withWindow<T>(_ windowId: UInt32, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> T?) async throws -> T? {
        try await thread?.runInLoop { [windows] job in
            guard let window = windows.threadGuarded[windowId] else { return nil }
            return try body(window.ax, job)
        }
    }

    private func withWindowAsync(_ windowId: UInt32, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> ()) -> RunLoopJob {
        thread?.runInLoopAsync { [windows] job in
            guard let window = windows.threadGuarded[windowId] else { return }
            try? body(window.ax, job)
        } ?? .cancelled
    }
}

func shouldUseActivationOnlyForNativeFocus(
    targetWindowId: UInt32,
    lastNativeFocusedWindowId: UInt32?,
    logicalWindowsCount: Int,
) -> Bool {
    lastNativeFocusedWindowId == targetWindowId || logicalWindowsCount == 1
}
