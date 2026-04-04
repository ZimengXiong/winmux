import AppKit

/// First line of defence against lock screen
///
/// When you lock the screen, all accessibility API becomes unobservable (all attributes become empty, window id
/// becomes nil, etc.) which tricks AeroSpace into thinking that all windows were closed.
/// That's why every time a window dies AeroSpace caches the "entire world" (unless window is already presented in the cache)
/// so that once the screen is unlocked, AeroSpace could restore windows to where they were
@MainActor private var closedWindowsCache = FrozenWorld(workspaces: [], monitors: [], windowIds: [])

struct FrozenMonitor: Codable, Sendable {
    let topLeftCorner: CGPoint
    let visibleWorkspace: String

    @MainActor init(_ monitor: Monitor) {
        topLeftCorner = monitor.rect.topLeftCorner
        visibleWorkspace = monitor.activeWorkspace.name
    }
}

struct FrozenWorkspace: Codable, Sendable {
    let name: String
    let namingStyle: WorkspaceNamingStyle
    let monitor: FrozenMonitor // todo drop this property, once monitor to workspace assignment migrates to TreeNode
    let rootTilingNode: FrozenContainer
    let floatingWindows: [FrozenWindow]
    let macosUnconventionalWindows: [FrozenWindow]

    private enum CodingKeys: String, CodingKey {
        case name
        case namingStyle
        case monitor
        case rootTilingNode
        case floatingWindows
        case macosUnconventionalWindows
    }

    @MainActor init(_ workspace: Workspace) {
        name = workspace.name
        namingStyle = workspace.namingStyle
        monitor = FrozenMonitor(workspace.workspaceMonitor)
        rootTilingNode = FrozenContainer(workspace.rootTilingContainer)
        floatingWindows = workspace.floatingWindows.map(FrozenWindow.init)
        macosUnconventionalWindows =
            workspaceOwnedMinimizedWindows(workspace).map(FrozenWindow.init) +
            (workspace.existingMacOsNativeHiddenAppsWindowsContainer?.children.map { FrozenWindow($0 as! Window) } ?? []) +
            (workspace.existingMacOsNativeFullscreenWindowsContainer?.children.map { FrozenWindow($0 as! Window) } ?? [])
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        namingStyle = try container.decodeIfPresent(WorkspaceNamingStyle.self, forKey: .namingStyle) ?? .explicit
        monitor = try container.decode(FrozenMonitor.self, forKey: .monitor)
        rootTilingNode = try container.decode(FrozenContainer.self, forKey: .rootTilingNode)
        floatingWindows = try container.decode([FrozenWindow].self, forKey: .floatingWindows)
        macosUnconventionalWindows = try container.decode([FrozenWindow].self, forKey: .macosUnconventionalWindows)
    }
}

@MainActor func cacheClosedWindowIfNeeded() {
    let frozenWorld = snapshotCurrentFrozenWorld()
    if frozenWorld.windowIds.isSubset(of: closedWindowsCache.windowIds) {
        return // already cached
    }
    closedWindowsCache = frozenWorld
}

@MainActor
func replaceClosedWindowsCache(_ frozenWorld: FrozenWorld) {
    closedWindowsCache = frozenWorld
}

@MainActor
func syncClosedWindowsCacheToCurrentWorld() {
    closedWindowsCache = snapshotCurrentFrozenWorld()
}

@MainActor func restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: Window) async throws -> Bool {
    try await restoreFrozenWorldIfNeeded(closedWindowsCache, newlyDetectedWindow: newlyDetectedWindow)
}

@MainActor
func restoreFrozenWorldIfNeeded(_ frozenWorld: FrozenWorld, newlyDetectedWindow: Window) async throws -> Bool {
    if !frozenWorld.windowIds.contains(newlyDetectedWindow.windowId) {
        return false
    }
    let monitors = monitors
    let topLeftCornerToMonitor = monitors.grouped { $0.rect.topLeftCorner }
    let restoredWorkspaceNames = Set(frozenWorld.workspaces.map(\.name))

    for frozenWorkspace in frozenWorld.workspaces {
        let workspace = Workspace.get(byName: frozenWorkspace.name)
        workspace.restoreNamingStyle(frozenWorkspace.namingStyle)
        let frozenWindowById = collectFrozenWindows(frozenWorkspace)
        _ = topLeftCornerToMonitor[frozenWorkspace.monitor.topLeftCorner]?
            .singleOrNil()?
            .setActiveWorkspace(workspace)
        for frozenWindow in frozenWorkspace.floatingWindows {
            if let window = Window.get(byId: frozenWindow.id) {
                applyFrozenWindowState(window, frozenWindow)
                window.bindAsFloatingWindow(to: workspace)
            }
        }
        for frozenWindow in frozenWorkspace.macosUnconventionalWindows {
            if let window = Window.get(byId: frozenWindow.id) {
                try await restoreFrozenUnconventionalWindow(window, frozenWindow, on: workspace)
            }
        }
        let prevRoot = workspace.rootTilingContainer // Save prevRoot into a variable to avoid it being garbage collected earlier than needed
        let potentialOrphans = prevRoot.allLeafWindowsRecursive
        prevRoot.unbindFromParent()
        restoreTreeRecursive(frozenContainer: frozenWorkspace.rootTilingNode, parent: workspace, index: INDEX_BIND_LAST)
        for window in (potentialOrphans - workspace.rootTilingContainer.allLeafWindowsRecursive) {
            if let frozenWindow = frozenWindowById[window.windowId] {
                if case .macos = frozenWindow.layoutReason {
                    try await restoreFrozenUnconventionalWindow(window, frozenWindow, on: workspace)
                    continue
                }
                applyFrozenWindowState(window, frozenWindow)
            }
            try await window.relayoutWindow(on: workspace, forceTile: true)
        }
    }

    for monitor in frozenWorld.monitors {
        guard let targetMonitor = topLeftCornerToMonitor[monitor.topLeftCorner]?.singleOrNil() else { continue }
        let targetWorkspace: Workspace
        if let existingVisibleWorkspace = Workspace.existing(byName: monitor.visibleWorkspace),
           restoredWorkspaceNames.contains(existingVisibleWorkspace.name) || existingVisibleWorkspace.isSystemStub
        {
            targetWorkspace = existingVisibleWorkspace
        } else {
            targetWorkspace = getStubWorkspace(for: targetMonitor)
        }
        _ = targetMonitor.setActiveWorkspace(targetWorkspace)
    }
    return true
}

@discardableResult
@MainActor
private func restoreTreeRecursive(frozenContainer: FrozenContainer, parent: NonLeafTreeNodeObject, index: Int) -> Bool {
    let container = TilingContainer(
        parent: parent,
        adaptiveWeight: frozenContainer.weight,
        frozenContainer.orientation,
        frozenContainer.layout,
        index: index,
    )

    for (index, child) in frozenContainer.children.enumerated() {
        switch child {
            case .window(let w):
                // Stop the loop if can't find the window, because otherwise all the subsequent windows will have incorrect index
                guard let window = Window.get(byId: w.id) else { return false }
                applyFrozenWindowState(window, w)
                window.bind(to: container, adaptiveWeight: w.weight, index: index)
            case .container(let c):
                // There is no reason to continue
                if !restoreTreeRecursive(frozenContainer: c, parent: container, index: index) { return false }
        }
    }
    return true
}

@MainActor
private func applyFrozenWindowState(_ window: Window, _ frozenWindow: FrozenWindow) {
    window.isFullscreen = frozenWindow.isFullscreen
    window.noOuterGapsInFullscreen = frozenWindow.noOuterGapsInFullscreen
    window.layoutReason = frozenWindow.layoutReason
}

@MainActor
private func restoreFrozenUnconventionalWindow(
    _ window: Window,
    _ frozenWindow: FrozenWindow,
    on workspace: Workspace,
) async throws {
    applyFrozenWindowState(window, frozenWindow)

    let isMacosFullscreen = try await window.isMacosFullscreen
    let isMacosMinimized = try await (!isMacosFullscreen).andAsync { @MainActor @Sendable in try await window.isMacosMinimized }
    let isMacosWindowOfHiddenApp = !isMacosFullscreen && !isMacosMinimized &&
        !config.automaticallyUnhideMacosHiddenApps && (window.app as? MacApp)?.nsApp.isHidden == true

    switch true {
        case isMacosFullscreen:
            window.bind(to: workspace.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
        case isMacosMinimized:
            window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        case isMacosWindowOfHiddenApp:
            window.bind(to: workspace.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
        default:
            switch frozenWindow.layoutReason {
                case .macos(let prevParentKind, let prevWorkspaceName):
                    try await exitMacOsNativeUnconventionalState(
                        window: window,
                        prevParentKind: prevParentKind,
                        prevWorkspaceName: prevWorkspaceName,
                        workspace: workspace,
                    )
                case .standard:
                    window.bindAsFloatingWindow(to: workspace)
            }
    }
}

private func collectFrozenWindows(_ frozenWorkspace: FrozenWorkspace) -> [UInt32: FrozenWindow] {
    var result = [UInt32: FrozenWindow]()
    for frozenWindow in frozenWorkspace.floatingWindows {
        result[frozenWindow.id] = frozenWindow
    }
    for frozenWindow in frozenWorkspace.macosUnconventionalWindows {
        result[frozenWindow.id] = frozenWindow
    }
    collectFrozenWindowsRecursive(frozenWorkspace.rootTilingNode, result: &result)
    return result
}

private func collectFrozenWindowsRecursive(_ frozenContainer: FrozenContainer, result: inout [UInt32: FrozenWindow]) {
    for child in frozenContainer.children {
        switch child {
            case .window(let frozenWindow):
                result[frozenWindow.id] = frozenWindow
            case .container(let container):
                collectFrozenWindowsRecursive(container, result: &result)
        }
    }
}

// Consider the following case:
// 1. Close window
// 2. The previous step lead to caching the whole world
// 3. Change something in the layout
// 4. Lock the screen
// 5. The cache won't be updated because all alive windows are already cached
// 6. Unlock the screen
// 7. The wrong cache is used
//
// That's why we have to refresh the cache every time layout or visible workspace assignment changes. Those changes can
// be caused by running commands and with mouse manipulations.
@MainActor func resetClosedWindowsCache() {
    closedWindowsCache = FrozenWorld(workspaces: [], monitors: [], windowIds: [])
}
