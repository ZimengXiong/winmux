import AppKit
import Common

@MainActor
private var activeRefreshTask: Task<(), any Error>? = nil

@MainActor
private var activeScheduledRefreshEvent: RefreshSessionEvent? = nil

@MainActor
private var activeScheduledRefreshGeneration: UInt64 = 0

@MainActor
private var scheduledRefreshOverrideForTests: (@MainActor @Sendable (RefreshSessionEvent, Bool) async throws -> Void)? = nil

@MainActor
private var refreshOverrideForTests: (@MainActor @Sendable () async throws -> Void)? = nil

@MainActor
private var normalizeLayoutReasonOverrideForTests: (@MainActor @Sendable () async throws -> Void)? = nil

private func isAxGeometryRefreshEvent(_ event: RefreshSessionEvent) -> Bool {
    guard case .ax(let notif) = event else { return false }
    return notif == kAXMovedNotification as String || notif == kAXResizedNotification as String
}

private func shouldDropScheduledRefresh(_ newEvent: RefreshSessionEvent, activeEvent: RefreshSessionEvent?) -> Bool {
    guard isAxGeometryRefreshEvent(newEvent), let activeEvent else { return false }
    if isAxGeometryRefreshEvent(activeEvent) {
        return true
    }
    if case .resetManipulatedWithMouse = activeEvent {
        return true
    }
    return false
}

@MainActor
func shouldSyncFocusBackToMacOs(
    nativeFocused: Window?,
    frontmostActivationPolicy: NSApplication.ActivationPolicy?,
) -> Bool {
    if nativeFocused?.participatesInWorkspaceFocus == false {
        return false
    }
    if nativeFocused == nil && frontmostActivationPolicy == .accessory {
        return false
    }
    return true
}

@MainActor
private var pendingRefreshRequest: (event: RefreshSessionEvent, optimisticallyPreLayoutWorkspaces: Bool)? = nil

/// When two refresh requests coalesce, keep the event whose session does more work, so the
/// follow-up session covers the requirements of every event that arrived while one was running.
private func mergeRefreshEvents(_ old: RefreshSessionEvent, _ new: RefreshSessionEvent) -> RefreshSessionEvent {
    func score(_ e: RefreshSessionEvent) -> Int {
        (e.requiresWindowRefreshBarrier ? 2 : 0) + (e.canReuseLastAppliedWindowFrames ? 0 : 1)
    }
    return score(new) >= score(old) ? new : old
}

@MainActor
func scheduleRefreshSession(
    _ event: RefreshSessionEvent,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) {
    if shouldDropScheduledRefresh(event, activeEvent: activeScheduledRefreshEvent) ||
        shouldDropScheduledRefresh(event, activeEvent: pendingRefreshRequest?.event)
    {
        debugFocusLog("scheduleRefreshSession dropped event=\(event) active=\(activeScheduledRefreshEvent?.description ?? "nil") pending=\(pendingRefreshRequest?.event.description ?? "nil")")
        return
    }
    // Coalesce instead of cancel-and-restart: cancelling the in-flight session on every event
    // meant that during event bursts (app launch, window storms) the refresh kept restarting
    // and never completed until the burst quieted down. Let the active session finish, then
    // run a single follow-up session on behalf of all events that arrived in the meantime.
    if activeRefreshTask != nil {
        pendingRefreshRequest = pendingRefreshRequest.map {
            (mergeRefreshEvents($0.event, event), $0.optimisticallyPreLayoutWorkspaces || optimisticallyPreLayoutWorkspaces)
        } ?? (event, optimisticallyPreLayoutWorkspaces)
        return
    }
    activeScheduledRefreshGeneration += 1
    let generation = activeScheduledRefreshGeneration
    activeScheduledRefreshEvent = event
    let override = scheduledRefreshOverrideForTests
    activeRefreshTask = Task { @MainActor in
        defer {
            // Generation mismatch means someone took over (light session, test setup); they are
            // responsible for the next refresh, so don't drain the pending request from here.
            if activeScheduledRefreshGeneration == generation {
                activeRefreshTask = nil
                activeScheduledRefreshEvent = nil
                if let pending = pendingRefreshRequest {
                    pendingRefreshRequest = nil
                    scheduleRefreshSession(pending.event, optimisticallyPreLayoutWorkspaces: pending.optimisticallyPreLayoutWorkspaces)
                }
            }
        }
        do {
            try checkCancellation()
            if let override {
                try await override(event, optimisticallyPreLayoutWorkspaces)
            } else {
                try await runRefreshSessionBlocking(event, optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
            }
        } catch is CancellationError {
            return
        }
    }
}

@MainActor
func runRefreshSessionBlocking(
    _ event: RefreshSessionEvent,
    layoutWorkspaces shouldLayoutWorkspaces: Bool = true,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) async throws {
    let state = signposter.beginInterval(#function, "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer { signposter.endInterval(#function, state) }
    if !TrayMenuModel.shared.isEnabled { return }
    let focusSnapshot = captureRefreshSessionFocusSnapshot()
    debugFocusLog("runRefreshSessionBlocking begin event=\(event) snapshot=\(debugDescribe(focusSnapshot))")
    try await $refreshSessionEvent.withValue(event) {
        try await $_isStartup.withValue(event.isStartup) {
            try await $_refreshSessionFocusSnapshot.withValue(focusSnapshot) {
                let frontmostActivationPolicy = NSWorkspace.shared.frontmostApplication?.activationPolicy
                let nativeFocused = try await getNativeFocusedWindow()
                try checkCancellation()
                if let nativeFocused { try await debugWindowsIfRecording(nativeFocused) }
                await updateNativeFullscreenChromeSuppression(nativeFocused: nativeFocused)
                updateFocusCache(nativeFocused)
                try checkCancellation()

                if shouldLayoutWorkspaces && optimisticallyPreLayoutWorkspaces { try await layoutWorkspaces() }
                try checkCancellation()

                refreshModel()
                if event.requiresWindowRefreshBarrier {
                    if let refreshOverrideForTests {
                        try await refreshOverrideForTests()
                    } else {
                        try await refresh()
                    }
                    try checkCancellation()
                    gcMonitors()
                }

                if event.requiresLayoutReasonNormalization {
                    if let normalizeLayoutReasonOverrideForTests {
                        try await normalizeLayoutReasonOverrideForTests()
                    } else {
                        try await normalizeLayoutReason()
                    }
                    try checkCancellation()
                    refreshModel()
                }
                updateTrayText()
                await updateWorkspaceSidebarModel()
                SecureInputPanel.shared.refresh()
                if shouldLayoutWorkspaces {
                    try await layoutWorkspaces()
                    try checkCancellation()
                    if shouldSyncFocusBackToMacOs(
                        nativeFocused: nativeFocused,
                        frontmostActivationPolicy: frontmostActivationPolicy,
                    ) {
                        let logicalFocused = focus.windowOrNil
                        if logicalFocused?.windowId != nativeFocused?.windowId {
                            debugFocusLog(
                                "runRefreshSessionBlocking syncFocus event=\(event) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") logicalFocused=\(logicalFocused?.windowId.description ?? "nil")"
                            )
                            logicalFocused?.nativeFocus()
                        } else {
                            debugFocusLog(
                                "runRefreshSessionBlocking skipSyncFocus event=\(event) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") logicalFocused=\(logicalFocused?.windowId.description ?? "nil")"
                            )
                        }
                    }
                }
                await updateWindowTabModel()
                debugFocusLog("runRefreshSessionBlocking end event=\(event) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") focus=\(debugDescribe(focus))")
            }
        }
    }
}

@MainActor
func runLightSession<T>(
    _ event: RefreshSessionEvent,
    _: RunSessionGuard,
    shouldSchedulePostRefresh: Bool = true,
    body: @MainActor () async throws -> T,
) async throws -> T {
    let state = signposter.beginInterval(#function, "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer { signposter.endInterval(#function, state) }
    activeRefreshTask?.cancel() // Give priority to runSession
    activeRefreshTask = nil
    // Invalidate the cancelled task's generation so its defer doesn't spawn a coalesced
    // follow-up session in the middle of this light session. The post-refresh scheduled at
    // the end of the light session (or any later event) picks the pending request up instead.
    activeScheduledRefreshGeneration += 1
    let focusSnapshot = captureRefreshSessionFocusSnapshot()
    debugFocusLog("runLightSession begin event=\(event) snapshot=\(debugDescribe(focusSnapshot))")
    return try await $refreshSessionEvent.withValue(event) {
        try await $_isStartup.withValue(event.isStartup) {
            try await $_refreshSessionFocusSnapshot.withValue(focusSnapshot) {
                let nativeFocused = try await getNativeFocusedWindow()
                try checkCancellation()
                if let nativeFocused { try await debugWindowsIfRecording(nativeFocused) }
                await updateNativeFullscreenChromeSuppression(nativeFocused: nativeFocused)
                updateFocusCache(nativeFocused)
                try checkCancellation()
                let focusBefore = focus.windowOrNil

                refreshModel()
                let result = try await body()
                try checkCancellation()
                refreshModel()

                let focusAfter = focus.windowOrNil

                updateTrayText()
                await updateWorkspaceSidebarModel()
                SecureInputPanel.shared.refresh()
                try await layoutWorkspaces()
                try checkCancellation()
                await updateWindowTabModel()
                if focusBefore != focusAfter {
                    focusAfter?.nativeFocus() // syncFocusToMacOs
                }
                if shouldSchedulePostRefresh {
                    scheduleRefreshSession(event)
                }
                debugFocusLog("runLightSession end event=\(event) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") focusBefore=\(focusBefore?.windowId.description ?? "nil") focusAfter=\(focusAfter?.windowId.description ?? "nil") logicalFocus=\(debugDescribe(focus))")
                return result
            }
        }
    }
}

@MainActor
func setScheduledRefreshOverrideForTests(
    _ override: (@MainActor @Sendable (RefreshSessionEvent, Bool) async throws -> Void)?
) {
    activeRefreshTask?.cancel()
    activeRefreshTask = nil
    activeScheduledRefreshEvent = nil
    pendingRefreshRequest = nil
    scheduledRefreshOverrideForTests = override
}

@MainActor
func setBlockingRefreshOverridesForTests(
    refresh: (@MainActor @Sendable () async throws -> Void)? = nil,
    normalizeLayoutReason: (@MainActor @Sendable () async throws -> Void)? = nil,
) {
    activeRefreshTask?.cancel()
    activeRefreshTask = nil
    activeScheduledRefreshEvent = nil
    pendingRefreshRequest = nil
    refreshOverrideForTests = refresh
    normalizeLayoutReasonOverrideForTests = normalizeLayoutReason
}

@MainActor
func waitForScheduledRefreshForTests() async throws {
    // A completing session may schedule a coalesced follow-up session; drain until quiet.
    for _ in 0 ..< 100 {
        guard let task = activeRefreshTask else { return }
        activeRefreshTask = nil
        try await task.value
    }
}

struct RunSessionGuard: Sendable {
    @MainActor
    static var isServerEnabled: RunSessionGuard? { TrayMenuModel.shared.isEnabled ? forceRun : nil }
    @MainActor
    static func isServerEnabled(orIsEnableCommand command: (any Command)?) -> RunSessionGuard? {
        command is EnableCommand ? .forceRun : .isServerEnabled
    }
    @MainActor
    static func checkServerIsEnabledOrDie(
        file: StaticString = #fileID,
        line: Int = #line,
        column: Int = #column,
        function: String = #function,
    ) -> RunSessionGuard {
        .isServerEnabled ?? dieT("server is disabled", file: file, line: line, column: column, function: function)
    }
    static let forceRun = RunSessionGuard()
    private init() {}
}

@MainActor
func refreshModel() {
    Workspace.reconcileWorkspaceState()
    checkOnFocusChangedCallbacks()
    normalizeContainers()
}

@MainActor
private func refresh() async throws {
    // Garbage collect terminated apps and windows before working with all windows
    let mapping = try await MacApp.refreshAllAndGetAliveWindowIds(frontmostAppBundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    let aliveWindowIds = mapping.values.flatMap { $0 }.toSet()

    for window in MacWindow.allWindows {
        if !aliveWindowIds.contains(window.windowId) {
            window.garbageCollect(skipClosedWindowsCache: false)
        }
    }
    // One task per app so the per-window AX round-trips of different apps overlap;
    // a single slow app no longer delays every other app's window registration.
    try await withThrowingTaskGroup(of: Void.self) { group in
        for (app, windowIds) in mapping {
            group.addTask { @Sendable @MainActor in
                for windowId in windowIds {
                    try await MacWindow.getOrRegister(windowId: windowId, macApp: app)
                }
            }
        }
        try await group.waitForAll()
    }
    finalizePersistedFrozenWorldAfterRefresh(aliveWindowIds: aliveWindowIds)

    // Garbage collect workspaces after apps, because workspaces contain apps.
    Workspace.reconcileWorkspaceState()
}

func refreshObs(_: AXObserver, _: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let notif = notif as String
    if notif == kAXFocusedWindowChangedNotification as String || notif == kAXUIElementDestroyedNotification as String {
        debugFocusLog("refreshObs notif=\(notif)")
    }
    Task { @MainActor in
        if !TrayMenuModel.shared.isEnabled { return }
        scheduleRefreshSession(.ax(notif))
    }
}

enum OptimalHideCorner {
    case bottomLeftCorner, bottomRightCorner
}

@MainActor
private func layoutWorkspaces() async throws {
    if !TrayMenuModel.shared.isEnabled {
        for workspace in Workspace.all {
            workspace.allLeafWindowsRecursive.forEach { window in
                guard let macWindow = window as? MacWindow else { return }
                if shouldKeepWindowHiddenForVisibleWorkspaceLayout(window) {
                    return
                }
                macWindow.unhideFromCorner()
            }
            try await workspace.layoutWorkspace() // Unhide tiling windows from corner
        }
        return
    }
    let monitors = monitors
    var monitorToOptimalHideCorner: [CGPoint: OptimalHideCorner] = [:]
    for monitor in monitors {
        let xOff = monitor.width * 0.1
        let yOff = monitor.height * 0.1
        // brc = bottomRightCorner
        let brc1 = monitor.rect.bottomRightCorner + CGPoint(x: 2, y: -yOff)
        let brc2 = monitor.rect.bottomRightCorner + CGPoint(x: -xOff, y: 2)
        let brc3 = monitor.rect.bottomRightCorner + CGPoint(x: 2, y: 2)

        // blc = bottomLeftCorner
        let blc1 = monitor.rect.bottomLeftCorner + CGPoint(x: -2, y: -yOff)
        let blc2 = monitor.rect.bottomLeftCorner + CGPoint(x: xOff, y: 2)
        let blc3 = monitor.rect.bottomLeftCorner + CGPoint(x: -2, y: 2)

        func contains(_ monitor: Monitor, _ point: CGPoint) -> Int { monitor.rect.contains(point) ? 1 : 0 }
        let important = 10

        let corner: OptimalHideCorner =
            monitors.sumOfInt { contains($0, blc1) + contains($0, blc2) + important * contains($0, blc3) } <
            monitors.sumOfInt { contains($0, brc1) + contains($0, brc2) + important * contains($0, brc3) }
            ? .bottomLeftCorner
            : .bottomRightCorner
        monitorToOptimalHideCorner[monitor.rect.topLeftCorner] = corner
    }

    // to reduce flicker, first unhide visible workspaces, then hide invisible ones
    for monitor in monitors {
        let workspace = monitor.activeWorkspace
        workspace.allLeafWindowsRecursive.forEach { window in
            guard let macWindow = window as? MacWindow else { return }
            if shouldKeepWindowHiddenForVisibleWorkspaceLayout(window) {
                return
            }
            macWindow.unhideFromCorner()
        }
        try await workspace.layoutWorkspace()
    }
    for workspace in Workspace.all where !workspace.isVisible {
        let corner = monitorToOptimalHideCorner[workspace.workspaceMonitor.rect.topLeftCorner] ?? .bottomRightCorner
        let shouldReassertHiddenWindows = refreshSessionEvent?.canReuseLastAppliedWindowFrames != true
        for window in workspace.allLeafWindowsRecursive {
            guard let macWindow = window as? MacWindow else { continue }
            macWindow.lastAppliedLayoutPhysicalRect = nil
            macWindow.lastAppliedLayoutVirtualRect = nil
            try await macWindow.hideInCorner(corner, force: shouldReassertHiddenWindows)
        }
    }
}

@MainActor
private func shouldKeepWindowHiddenForVisibleWorkspaceLayout(_ window: Window) -> Bool {
    guard let tabGroup = window.nearestWindowTabGroup, tabGroup.usesWindowTabBehavior else { return false }
    return tabGroup.tabActiveWindow != window
}

@MainActor
private func normalizeContainers() {
    // Can't do it only for visible workspace because most of the commands support --window-id and --workspace flags
    for workspace in Workspace.all {
        workspace.normalizeContainers()
    }
}
