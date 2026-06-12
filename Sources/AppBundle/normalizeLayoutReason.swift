@MainActor
func normalizeLayoutReason() async throws {
    for workspace in Workspace.all {
        let windows: [Window] = workspace.allLeafWindowsRecursive
        try await _normalizeLayoutReason(workspace: workspace, windows: windows)
    }
    try await _normalizeLayoutReason(workspace: focus.workspace, windows: macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self))
    try await validateStillPopups()
}

@MainActor
private func validateStillPopups() async throws {
    for node in macosPopupWindowsContainer.children {
        guard let popup = node as? MacWindow else { continue }
        let windowLevel = getWindowLevel(for: popup.windowId)
        if try await popup.isWindowHeuristic(windowLevel) {
            try await popup.relayoutWindow(on: focus.workspace)
            try await tryOnWindowDetected(popup)
        }
    }
}

@MainActor
private func _normalizeLayoutReason(workspace: Workspace, windows: [Window]) async throws {
    // Phase 1: gather AX state with one concurrent task per window, so round-trips to different
    // apps overlap instead of serializing (2 sequential AX round-trips per window adds up fast).
    // Phase 2: apply tree mutations sequentially to keep binding order deterministic.
    var axState = [(isMacosFullscreen: Bool, isMacosMinimized: Bool)?](repeating: nil, count: windows.count)
    try await withThrowingTaskGroup(of: (Int, Bool, Bool).self) { group in
        for (index, window) in windows.enumerated() {
            group.addTask { @Sendable @MainActor in
                let isMacosFullscreen = try await window.isMacosFullscreen
                let isMacosMinimized = try await (!isMacosFullscreen).andAsync { @MainActor @Sendable in try await window.isMacosMinimized }
                return (index, isMacosFullscreen, isMacosMinimized)
            }
        }
        for try await (index, isFullscreen, isMinimized) in group {
            axState[index] = (isFullscreen, isMinimized)
        }
    }
    for (index, window) in windows.enumerated() {
        guard let (isMacosFullscreen, isMacosMinimized) = axState[index] else { continue }
        let isMacosWindowOfHiddenApp = !isMacosFullscreen && !isMacosMinimized &&
            !config.automaticallyUnhideMacosHiddenApps && window.macAppUnsafe.nsApp.isHidden
        switch window.layoutReason {
            case .standard:
                guard window.parent != nil else { continue }
                switch true {
                    case isMacosFullscreen:
                        window.rememberMacOsLayoutOrigin()
                        window.bind(to: workspace.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                    case isMacosMinimized:
                        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)
                        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
                    case isMacosWindowOfHiddenApp:
                        window.rememberMacOsLayoutOrigin()
                        window.bind(to: workspace.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                    default: break
                }
            case .macos(let prevParentKind, let prevWorkspaceName):
                if !isMacosFullscreen && !isMacosMinimized && !isMacosWindowOfHiddenApp {
                    try await exitMacOsNativeUnconventionalState(
                        window: window,
                        prevParentKind: prevParentKind,
                        prevWorkspaceName: prevWorkspaceName,
                        workspace: workspace,
                    )
                }
        }
    }
}

@MainActor
func exitMacOsNativeUnconventionalState(
    window: Window,
    prevParentKind: NonLeafTreeNodeKind,
    prevWorkspaceName: String?,
    workspace fallbackWorkspace: Workspace,
) async throws {
    window.layoutReason = .standard
    let workspace = prevWorkspaceName
        .flatMap { Workspace.existing(byName: $0) }
        ?? fallbackWorkspace
    workspace.seedMonitorIfNeeded(fallbackWorkspace.workspaceMonitor)
    switch prevParentKind {
        case .workspace:
            window.bindAsFloatingWindow(to: workspace)
        case .tilingContainer:
            try await window.relayoutWindow(on: workspace, forceTile: true)
        case .macosPopupWindowsContainer: // Since the window was minimized/fullscreened it was mistakenly detected as popup. Relayout the window
            try await window.relayoutWindow(on: workspace)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer: // wtf case, should never be possible. But If encounter it, let's just re-layout window
            try await window.relayoutWindow(on: workspace)
    }
}
