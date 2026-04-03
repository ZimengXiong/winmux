import AppKit
import Common

enum EffectiveLeaf {
    case window(Window)
    case emptyWorkspace(Workspace)
}
extension LiveFocus {
    var asLeaf: EffectiveLeaf {
        if let windowOrNil { .window(windowOrNil) } else { .emptyWorkspace(workspace) }
    }
}

/// This object should be only passed around but never memorized
/// Alternative name: ResolvedFocus
struct LiveFocus: AeroAny, Equatable {
    let windowOrNil: Window?
    var workspace: Workspace

    @MainActor fileprivate var frozen: FrozenFocus {
        return FrozenFocus(
            windowId: windowOrNil?.windowId,
            workspaceName: workspace.name,
            monitorId_oneBased: workspace.workspaceMonitor.monitorId_oneBased ?? 0,
        )
    }
}

/// "old", "captured", "frozen in time" Focus
/// It's safe to keep a hard reference to this object.
/// Unlike in LiveFocus, information inside FrozenFocus isn't guaranteed to be self-consistent.
/// window - workspace - monitor relation could change since the moment object was created
struct FrozenFocus: AeroAny, Equatable, Sendable {
    let windowId: UInt32?
    let workspaceName: String
    // monitorId is not part of the focus. We keep it here only for 'on-focused-monitor-changed' to work
    let monitorId_oneBased: Int

    @MainActor var liveOrNil: LiveFocus? { // Important: don't access focus.monitorId here. monitorId is not part of the focus. Always prefer workspace
        let window: Window? = windowId.flatMap { Window.get(byId: $0) }
        guard let workspace = Workspace.existing(byName: workspaceName) else { return nil }

        let workspaceFocus = workspace.toLiveFocus()
        let windowFocus = window?.takeIf(\.participatesInWorkspaceFocus)?.toLiveFocusOrNil() ?? workspaceFocus

        return workspaceFocus.workspace != windowFocus.workspace
            ? workspaceFocus // If window and workspace become separated prefer workspace
            : windowFocus
    }

    @MainActor var live: LiveFocus { liveOrNil ?? mainMonitor.activeWorkspace.toLiveFocus() }
}

struct RefreshSessionFocusSnapshot: Sendable {
    let focus: FrozenFocus
    let prevFocus: FrozenFocus?
    let prevPrevFocus: FrozenFocus?
    let fallbackWhenFocusedWindowCloses: FrozenFocus?
}

@TaskLocal
var _refreshSessionFocusSnapshot: RefreshSessionFocusSnapshot? = nil
var refreshSessionFocusSnapshot: RefreshSessionFocusSnapshot? { _refreshSessionFocusSnapshot }

@MainActor
func captureRefreshSessionFocusSnapshot() -> RefreshSessionFocusSnapshot {
    let currentFocus = focus
    return RefreshSessionFocusSnapshot(
        focus: _focus,
        prevFocus: _prevFocus,
        prevPrevFocus: _prevPrevFocus,
        fallbackWhenFocusedWindowCloses: currentFocus.windowOrNil.map { currentFocus.workspace.toLiveFocus(excluding: $0).frozen },
    )
}

func debugDescribe(_ focus: LiveFocus?) -> String {
    guard let focus else { return "nil" }
    return "w:\(focus.windowOrNil?.windowId.description ?? "nil") ws:\(focus.workspace.name)"
}

func debugDescribe(_ focus: FrozenFocus?) -> String {
    guard let focus else { return "nil" }
    return "w:\(focus.windowId?.description ?? "nil") ws:\(focus.workspaceName)"
}

@MainActor
func debugDescribe(_ snapshot: RefreshSessionFocusSnapshot?) -> String {
    guard let snapshot else { return "nil" }
    return "focus[\(debugDescribe(snapshot.focus.liveOrNil))] prev[\(debugDescribe(snapshot.prevFocus?.liveOrNil))] prevPrev[\(debugDescribe(snapshot.prevPrevFocus?.liveOrNil))] closeFallback[\(debugDescribe(snapshot.fallbackWhenFocusedWindowCloses?.liveOrNil))]"
}

@MainActor private var _focus: FrozenFocus = {
    let monitor = mainMonitor
    return FrozenFocus(windowId: nil, workspaceName: monitor.activeWorkspace.name, monitorId_oneBased: monitor.monitorId_oneBased ?? 0)
}()

/// Global focus.
/// Commands must be cautious about accessing this property directly. There are legitimate cases.
/// But, in general, commands must firstly check --window-id, --workspace, AEROSPACE_WINDOW_ID env and
/// AEROSPACE_WORKSPACE env before accessing the global focus.
@MainActor var focus: LiveFocus { _focus.live }

@MainActor func setFocus(to newFocus: LiveFocus) -> Bool {
    if _focus == newFocus.frozen { return true }
    let oldFocus = focus
    // Normalize mruWindow when focus away from a workspace
    if oldFocus.workspace != newFocus.workspace {
        oldFocus.windowOrNil?.markAsMostRecentChild()
    }

    _focus = newFocus.frozen
    let status = newFocus.workspace.workspaceMonitor.setActiveWorkspace(newFocus.workspace)

    newFocus.windowOrNil?.markAsMostRecentChild()
    return status
}
extension Window {
    @MainActor func focusWindow() -> Bool {
        if let focus = toLiveFocusOrNil() {
            return setFocus(to: focus)
        } else {
            // todo We should also exit-native-hidden/unminimize[/exit-native-fullscreen?] window if we want to fix ID-B6E178F2
            //      and retry to focus the window. Otherwise, it's not possible to focus minimized/hidden windows
            return false
        }
    }

    @MainActor func toLiveFocusOrNil() -> LiveFocus? { visualWorkspace.map { LiveFocus(windowOrNil: self, workspace: $0) } }
}
extension Workspace {
    @MainActor func focusWorkspace() -> Bool { setFocus(to: toLiveFocus()) }

    func toLiveFocus() -> LiveFocus {
        toLiveFocus(excluding: nil)
    }

    func toLiveFocus(excluding excludedWindow: Window?) -> LiveFocus {
        if let wd = mostRecentWorkspaceFocusableWindowRecursive(excluding: excludedWindow) {
            LiveFocus(windowOrNil: wd, workspace: self)
        } else {
            LiveFocus(windowOrNil: nil, workspace: self) // emptyWorkspace
        }
    }
}

@MainActor private var _lastKnownFocus: FrozenFocus = _focus

// Used by workspace-back-and-forth
@MainActor var _prevFocusedWorkspaceName: String? = nil {
    didSet {
        prevFocusedWorkspaceDate = .now
    }
}
@MainActor var prevFocusedWorkspaceDate: Date = .distantPast
@MainActor var prevFocusedWorkspace: Workspace? { _prevFocusedWorkspaceName.flatMap(Workspace.existing(byName:)) }

// Used by focus-back-and-forth
@MainActor private var _prevFocus: FrozenFocus? = nil
@MainActor var prevFocus: LiveFocus? {
    guard let prevFocus = _prevFocus?.liveOrNil, prevFocus != focus else { return nil }
    return prevFocus
}
@MainActor private var _prevPrevFocus: FrozenFocus? = nil
@MainActor var prevPrevFocus: LiveFocus? {
    guard let prevPrevFocus = _prevPrevFocus?.liveOrNil, prevPrevFocus != focus else { return nil }
    return prevPrevFocus
}

@MainActor private var onFocusChangedRecursionGuard = false
// Should be called in refreshSession
@MainActor func checkOnFocusChangedCallbacks() {
    if refreshSessionEvent?.isStartup == true {
        return
    }
    let focus = focus
    let frozenFocus = focus.frozen
    let lastKnownFocusBefore = _lastKnownFocus
    let prevFocusBefore = _prevFocus
    let prevPrevFocusBefore = _prevPrevFocus
    var hasFocusChanged = false
    var hasFocusedWorkspaceChanged = false
    var hasFocusedMonitorChanged = false
    if frozenFocus != _lastKnownFocus {
        _prevPrevFocus = _prevFocus
        _prevFocus = _lastKnownFocus
        hasFocusChanged = true
    }
    if frozenFocus.workspaceName != _lastKnownFocus.workspaceName {
        _prevFocusedWorkspaceName = _lastKnownFocus.workspaceName
        hasFocusedWorkspaceChanged = true
    }
    if frozenFocus.monitorId_oneBased != _lastKnownFocus.monitorId_oneBased {
        hasFocusedMonitorChanged = true
    }
    _lastKnownFocus = frozenFocus

    if onFocusChangedRecursionGuard { return }
    onFocusChangedRecursionGuard = true
    defer { onFocusChangedRecursionGuard = false }
    if hasFocusChanged {
        onFocusChanged(focus)
    }
    if let _prevFocusedWorkspaceName, hasFocusedWorkspaceChanged {
        onWorkspaceChanged(_prevFocusedWorkspaceName, frozenFocus.workspaceName)
    }
    if hasFocusedMonitorChanged {
        onFocusedMonitorChanged(focus)
    }
    if hasFocusChanged {
        debugFocusLog(
            "checkOnFocusChangedCallbacks event=\(refreshSessionEvent.prettyDescription) lastKnown=\(debugDescribe(lastKnownFocusBefore.liveOrNil)) -> focus=\(debugDescribe(focus)) prev=\(debugDescribe(prevFocusBefore?.liveOrNil)) -> \(debugDescribe(_prevFocus?.liveOrNil)) prevPrev=\(debugDescribe(prevPrevFocusBefore?.liveOrNil)) -> \(debugDescribe(_prevPrevFocus?.liveOrNil))"
        )
    }
}

@MainActor private func onFocusedMonitorChanged(_ focus: LiveFocus) {
    broadcastEvent(.focusedMonitorChanged(
        workspace: focus.workspace.name,
        monitorId_oneBased: focus.workspace.workspaceMonitor.monitorId_oneBased ?? 0,
    ))
    if config.onFocusedMonitorChanged.isEmpty { return }
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    // todo potential optimization: don't run runSession if we are already in runSession
    Task {
        try await runLightSession(.onFocusedMonitorChanged, token) {
            _ = try await config.onFocusedMonitorChanged.runCmdSeq(.defaultEnv.withFocus(focus), .emptyStdin)
        }
    }
}
@MainActor private func onFocusChanged(_ focus: LiveFocus) {
    broadcastEvent(.focusChanged(
        windowId: focus.windowOrNil?.windowId,
        workspace: focus.workspace.name,
    ))
    if config.onFocusChanged.isEmpty { return }
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    // todo potential optimization: don't run runSession if we are already in runSession
    Task {
        try await runLightSession(.onFocusChanged, token) {
            _ = try await config.onFocusChanged.runCmdSeq(.defaultEnv.withFocus(focus), .emptyStdin)
        }
    }
}

@MainActor private func onWorkspaceChanged(_ oldWorkspace: String, _ newWorkspace: String) {
    broadcastEvent(.workspaceChanged(
        workspace: newWorkspace,
        prevWorkspace: oldWorkspace,
    ))
    if let exec = config.execOnWorkspaceChange.first {
        let process = Process()
        process.executableURL = URL(filePath: exec)
        process.arguments = Array(config.execOnWorkspaceChange.dropFirst())
        var environment = config.execConfig.envVariables
        environment["AEROSPACE_FOCUSED_WORKSPACE"] = newWorkspace
        environment["AEROSPACE_PREV_WORKSPACE"] = oldWorkspace
        environment[AEROSPACE_WORKSPACE] = newWorkspace
        process.environment = environment
        _ = Result { try process.run() }
    }
}
