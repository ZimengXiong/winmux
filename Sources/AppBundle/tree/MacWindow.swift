import AppKit
import Common

final class MacWindow: Window {
    let macApp: MacApp
    private var prevUnhiddenProportionalPositionInsideWorkspaceRect: CGPoint?

    @MainActor
    private init(_ id: UInt32, _ actor: MacApp, lastFloatingSize: CGSize?, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) {
        self.macApp = actor
        super.init(id: id, actor, lastFloatingSize: lastFloatingSize, parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor static var allWindowsMap: [UInt32: MacWindow] = [:]
    @MainActor static var allWindows: [MacWindow] { Array(allWindowsMap.values) }

    @MainActor
    @discardableResult
    static func getOrRegister(windowId: UInt32, macApp: MacApp) async throws -> MacWindow {
        if let existing = allWindowsMap[windowId] { return existing }
        let rect = try await macApp.getAxRect(windowId)
        let data = try await unbindAndGetBindingDataForNewWindow(
            windowId,
            macApp,
            isStartup
                ? (rect?.center.monitorApproximation ?? mainMonitor).activeWorkspace
                : focus.workspace,
            window: nil,
        )

        // atomic synchronous section
        if let existing = allWindowsMap[windowId] { return existing }
        let window = MacWindow(windowId, macApp, lastFloatingSize: rect?.size, parent: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
        allWindowsMap[windowId] = window

        try await debugWindowsIfRecording(window)
        let didRestorePersistedFrozenWorld = try await restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: window)
        let didRestoreClosedWindowsCache = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
        if !didRestorePersistedFrozenWorld && !didRestoreClosedWindowsCache {
            try await tryOnWindowDetected(window)
        }
        return window
    }

    // var description: String {
    //     let description = [
    //         ("title", title),
    //         ("role", axWindow.get(Ax.roleAttr)),
    //         ("subrole", axWindow.get(Ax.subroleAttr)),
    //         ("identifier", axWindow.get(Ax.identifierAttr)),
    //         ("modal", axWindow.get(Ax.modalAttr).map { String($0) } ?? ""),
    //         ("windowId", String(windowId)),
    //     ].map { "\($0.0): '\(String(describing: $0.1))'" }.joined(separator: ", ")
    //     return "Window(\(description))"
    // }

    func isWindowHeuristic(_ windowLevel: MacOsWindowLevel?) async throws -> Bool { // todo cache
        try await macApp.isWindowHeuristic(windowId, windowLevel)
    }

    func isDialogHeuristic(_ windowLevel: MacOsWindowLevel?) async throws -> Bool { // todo cache
        try await macApp.isDialogHeuristic(windowId, windowLevel)
    }

    func dumpAxInfo() async throws -> [String: Json] {
        try await macApp.dumpWindowAxInfo(windowId: windowId)
    }

    func setNativeFullscreen(_ value: Bool) {
        macApp.setNativeFullscreen(windowId, value)
    }

    func setNativeMinimized(_ value: Bool) {
        macApp.setNativeMinimized(windowId, value)
    }

    // skipClosedWindowsCache is an optimization when it's definitely not necessary to cache closed window.
    //                        If you are unsure, it's better to pass `false`
    @MainActor
    func garbageCollect(skipClosedWindowsCache: Bool) {
        if MacWindow.allWindowsMap.removeValue(forKey: windowId) == nil {
            return
        }
        if !skipClosedWindowsCache { cacheClosedWindowIfNeeded() }
        let parent = unbindFromParent().parent
        let deadWindowWorkspace = parent.nodeWorkspace
        let currentFocus = focus
        let previousFocus = prevFocus
        let previousPreviousFocus = prevPrevFocus
        let refreshSnapshot = refreshSessionFocusSnapshot
        let refreshSnapshotCloseFallback = refreshSnapshot?.focus.windowId == windowId
            ? refreshSnapshot?.fallbackWhenFocusedWindowCloses?.liveOrNil
            : nil
        let refreshSnapshotPreviousFocus = refreshSessionFocusSnapshot?.prevFocus?.liveOrNil
        let refreshSnapshotPreviousPreviousFocus = refreshSessionFocusSnapshot?.prevPrevFocus?.liveOrNil
        debugFocusLog(
            "MacWindow.garbageCollect closing=\(windowId) currentFocus=\(debugDescribe(currentFocus)) prev=\(debugDescribe(previousFocus)) prevPrev=\(debugDescribe(previousPreviousFocus)) snapshot=\(debugDescribe(refreshSnapshot))"
        )
        if let replacementFocus = focusAfterWindowClosure(
            closingWindow: self,
            deadWindowWorkspace: deadWindowWorkspace,
            currentFocus: currentFocus,
            previousFocus: previousFocus,
            previousPreviousFocus: previousPreviousFocus,
            refreshSnapshotCloseFallback: refreshSnapshotCloseFallback,
            refreshSnapshotPreviousFocus: refreshSnapshotPreviousFocus,
            refreshSnapshotPreviousPreviousFocus: refreshSnapshotPreviousPreviousFocus,
            previousFocusedWorkspace: prevFocusedWorkspace,
            previousFocusedWorkspaceDate: prevFocusedWorkspaceDate,
        ) {
            switch parent.cases {
                case .tilingContainer, .workspace, .macosHiddenAppsWindowsContainer, .macosFullscreenWindowsContainer:
                    debugFocusLog("MacWindow.garbageCollect replacement closing=\(windowId) replacement=\(debugDescribe(replacementFocus))")
                    _ = setFocus(to: replacementFocus)
                    if replacementFocus.windowOrNil != currentFocus.windowOrNil {
                        replacementFocus.windowOrNil?.nativeFocus()
                    }
                case .macosPopupWindowsContainer, .macosMinimizedWindowsContainer:
                    break // Don't switch back on popup destruction
            }
        }
    }

    @MainActor override var title: String { get async throws { try await macApp.getAxTitle(windowId) ?? "" } }
    @MainActor override var isMacosFullscreen: Bool { get async throws { try await macApp.isMacosNativeFullscreen(windowId) == true } }
    @MainActor override var isMacosMinimized: Bool { get async throws { try await macApp.isMacosNativeMinimized(windowId) == true } }

    @MainActor
    override func nativeFocus() {
        macApp.nativeFocus(windowId)
    }

    override func closeAxWindow() {
        garbageCollect(skipClosedWindowsCache: true)
        macApp.closeAndUnregisterAxWindow(windowId)
    }

    // todo it's part of the window layout and should be moved to layoutRecursive.swift
    @MainActor
    func hideInCorner(_ corner: OptimalHideCorner) async throws {
        guard let nodeMonitor else { return }
        // Don't accidentally override prevUnhiddenEmulationPosition in case of subsequent `hideInCorner` calls
        if !isHiddenInCorner {
            guard let windowRect = try await getAxRect() else { return }
            // Check for isHiddenInCorner for the second time because of the suspension point above
            if !isHiddenInCorner {
                let topLeftCorner = windowRect.topLeftCorner
                let monitorRect = windowRect.center.monitorApproximation.rect // Similar to layoutFloatingWindow. Non idempotent
                let absolutePoint = topLeftCorner - monitorRect.topLeftCorner
                prevUnhiddenProportionalPositionInsideWorkspaceRect =
                    CGPoint(x: absolutePoint.x / monitorRect.width, y: absolutePoint.y / monitorRect.height)
            }
        }
        let p: CGPoint
        switch corner {
            case .bottomLeftCorner:
                guard let s = try await getAxSize() else { fallthrough }
                // Zoom will jump off if you do one pixel offset https://github.com/nikitabobko/AeroSpace/issues/527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.appId == .zoom ? .zero : CGPoint(x: 1, y: -1)
                p = nodeMonitor.visibleRect.bottomLeftCorner + onePixelOffset + CGPoint(x: -s.width, y: 0)
            case .bottomRightCorner:
                // Zoom will jump off if you do one pixel offset https://github.com/nikitabobko/AeroSpace/issues/527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.appId == .zoom ? .zero : CGPoint(x: 1, y: 1)
                p = nodeMonitor.visibleRect.bottomRightCorner - onePixelOffset
        }
        setAxFrame(p, nil)
    }

    @MainActor
    func unhideFromCorner() {
        guard let prevUnhiddenProportionalPositionInsideWorkspaceRect else { return }
        guard let nodeWorkspace else { return } // hiding only makes sense for workspace windows
        guard let parent else { return }

        switch getChildParentRelation(child: self, parent: parent) {
            // Just a small optimization to avoid unnecessary AX calls for non floating windows
            // Tiling windows should be unhidden with layoutRecursive anyway
            case .floatingWindow:
                let workspaceRect = nodeWorkspace.workspaceMonitor.rect
                var newX = workspaceRect.topLeftX + workspaceRect.width * prevUnhiddenProportionalPositionInsideWorkspaceRect.x
                var newY = workspaceRect.topLeftY + workspaceRect.height * prevUnhiddenProportionalPositionInsideWorkspaceRect.y
                // todo we probably should replace lastFloatingSize with proper floating window sizing
                // https://github.com/nikitabobko/AeroSpace/issues/1519
                let windowWidth = lastFloatingSize?.width ?? 0
                let windowHeight = lastFloatingSize?.height ?? 0
                newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
                newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))

                setAxFrame(CGPoint(x: newX, y: newY), nil)
            case .macosNativeFullscreenWindow, .macosNativeHiddenAppWindow, .macosNativeMinimizedWindow,
                 .macosPopupWindow, .tiling, .rootTilingContainer, .shimContainerRelation: break
        }

        self.prevUnhiddenProportionalPositionInsideWorkspaceRect = nil
    }

    override var isHiddenInCorner: Bool {
        prevUnhiddenProportionalPositionInsideWorkspaceRect != nil
    }

    override func getAxSize() async throws -> CGSize? {
        try await macApp.getAxSize(windowId)
    }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        macApp.setAxFrame(windowId, topLeft, size)
    }

    func setAxFrameBlocking(_ topLeft: CGPoint?, _ size: CGSize?) async throws {
        try await macApp.setAxFrameBlocking(windowId, topLeft, size)
    }

    override func getAxRect() async throws -> Rect? {
        try await macApp.getAxRect(windowId)
    }
}

@MainActor
func focusAfterWindowClosure(
    closingWindow: Window,
    deadWindowWorkspace: Workspace?,
    currentFocus: LiveFocus,
    previousFocus: LiveFocus?,
    previousPreviousFocus: LiveFocus?,
    refreshSnapshotCloseFallback: LiveFocus?,
    refreshSnapshotPreviousFocus: LiveFocus?,
    refreshSnapshotPreviousPreviousFocus: LiveFocus?,
    previousFocusedWorkspace: Workspace?,
    previousFocusedWorkspaceDate: Date,
    now: Date = .now,
) -> LiveFocus? {
    guard let deadWindowWorkspace else { return nil }
    guard deadWindowWorkspace == currentFocus.workspace ||
        deadWindowWorkspace == previousFocusedWorkspace && previousFocusedWorkspaceDate.distance(to: now) < 1
    else {
        debugFocusLog("focusAfterWindowClosure closing=\(closingWindow.windowId) skipped currentFocus=\(debugDescribe(currentFocus)) previousFocusedWorkspace=\(previousFocusedWorkspace?.name ?? "nil")")
        return nil
    }

    func isValidReplacement(_ candidate: LiveFocus?) -> Bool {
        candidate?.windowOrNil != closingWindow &&
            candidate?.workspace == deadWindowWorkspace &&
            candidate?.windowOrNil?.participatesInWorkspaceFocus != false
    }

    let fallbackHistory: [LiveFocus?] = [
        refreshSnapshotCloseFallback,
        refreshSnapshotPreviousFocus,
        previousFocus,
        (refreshSnapshotPreviousFocus?.windowOrNil == closingWindow) ? refreshSnapshotPreviousPreviousFocus : nil,
        (previousFocus?.windowOrNil == closingWindow) ? previousPreviousFocus : nil,
    ]
    for candidate in fallbackHistory where isValidReplacement(candidate) {
        debugFocusLog(
            "focusAfterWindowClosure closing=\(closingWindow.windowId) choseCandidate=\(debugDescribe(candidate)) current=\(debugDescribe(currentFocus)) snapshotCloseFallback=\(debugDescribe(refreshSnapshotCloseFallback)) snapshotPrev=\(debugDescribe(refreshSnapshotPreviousFocus)) snapshotPrevPrev=\(debugDescribe(refreshSnapshotPreviousPreviousFocus)) prev=\(debugDescribe(previousFocus)) prevPrev=\(debugDescribe(previousPreviousFocus))"
        )
        return candidate
    }

    let fallback = deadWindowWorkspace.toLiveFocus()
    debugFocusLog("focusAfterWindowClosure closing=\(closingWindow.windowId) defaultFallback=\(debugDescribe(fallback))")
    return fallback
}

extension Window {
    @MainActor
    func relayoutWindow(on workspace: Workspace, forceTile: Bool = false) async throws {
        let data = forceTile
            ? bindingDataForNewTilingWindow(workspace, window: self)
            : try await unbindAndGetBindingDataForNewWindow(self.asMacWindow().windowId, self.asMacWindow().macApp, workspace, window: self)
        bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
    }
}

// The function is private because it's unsafe. It leaves the window in unbound state
@MainActor
private func unbindAndGetBindingDataForNewWindow(_ windowId: UInt32, _ macApp: MacApp, _ workspace: Workspace, window: Window?) async throws -> BindingData {
    let workspace = materializeWorkspaceForUserWindowIfNeeded(workspace)
    let windowLevel = getWindowLevel(for: windowId)
    return switch try await macApp.getAxUiElementWindowType(windowId, windowLevel) {
        case .popup: BindingData(parent: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .dialog: BindingData(parent: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .window: bindingDataForNewTilingWindow(workspace, window: window)
    }
}

// The function is intentionally internal to make insertion semantics unit-testable.
// It is unsafe because it may leave `window` in unbound state.
@MainActor
func bindingDataForNewTilingWindow(_ workspace: Workspace, window: Window?) -> BindingData {
    let workspace = materializeWorkspaceForUserWindowIfNeeded(workspace)
    window?.unbindFromParent() // It's important to unbind to get correct data from below
    let mruWindow = workspace.mostRecentWindowRecursive
    if let mruWindow, let tilingParent = mruWindow.parent as? TilingContainer {
        if tilingParent.layout == .accordion {
            var insertionAnchor: TreeNode = tilingParent
            var insertionParent: NonLeafTreeNodeObject = tilingParent.parent.orDie()
            while let accordionParent = insertionParent as? TilingContainer, accordionParent.layout == .accordion {
                insertionAnchor = accordionParent
                insertionParent = accordionParent.parent.orDie()
            }
            switch insertionParent.cases {
                case .tilingContainer(let parent):
                    return BindingData(
                        parent: parent,
                        adaptiveWeight: WEIGHT_AUTO,
                        index: insertionAnchor.ownIndex.orDie() + 1,
                    )
                case .workspace:
                    let prevRoot = workspace.rootTilingContainer
                    if prevRoot === insertionAnchor {
                        prevRoot.unbindFromParent()
                        _ = TilingContainer(
                            parent: workspace,
                            adaptiveWeight: WEIGHT_AUTO,
                            tilingParent.orientation.opposite,
                            .tiles,
                            index: 0,
                        )
                        prevRoot.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: 0)
                    }
                    return BindingData(
                        parent: workspace.rootTilingContainer,
                        adaptiveWeight: WEIGHT_AUTO,
                        index: INDEX_BIND_LAST,
                    )
                case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                     .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer:
                    die("Impossible insertion parent for tiling window")
            }
        }
        return BindingData(
            parent: tilingParent,
            adaptiveWeight: WEIGHT_AUTO,
            index: mruWindow.ownIndex.orDie() + 1,
        )
    } else {
        return BindingData(
            parent: workspace.rootTilingContainer,
            adaptiveWeight: WEIGHT_AUTO,
            index: INDEX_BIND_LAST,
        )
    }
}

@MainActor
func tryOnWindowDetected(_ window: Window) async throws {
    guard let parent = window.parent else { return }
    switch parent.cases {
        case .tilingContainer, .workspace, .macosMinimizedWindowsContainer,
             .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
            try await onWindowDetected(window)
        case .macosPopupWindowsContainer:
            break
    }
}

@MainActor
private func onWindowDetected(_ window: Window) async throws {
    broadcastEvent(.windowDetected(
        windowId: window.windowId,
        workspace: window.nodeWorkspace?.name,
        appBundleId: window.app.rawAppBundleId,
        appName: window.app.name,
    ))
    for callback in config.onWindowDetected where try await callback.matches(window) {
        _ = try await callback.run.runCmdSeq(.defaultEnv.copy(\.windowId, window.windowId), .emptyStdin)
        if !callback.checkFurtherCallbacks {
            return
        }
    }
}

extension WindowDetectedCallback {
    @MainActor
    func matches(_ window: Window) async throws -> Bool {
        if let startupMatcher = matcher.duringAeroSpaceStartup, startupMatcher != isStartup {
            return false
        }
        if let regex = matcher.windowTitleRegexSubstring, !(try await window.title).contains(regex) {
            return false
        }
        if let appId = matcher.appId, appId != window.app.rawAppBundleId {
            return false
        }
        if let regex = matcher.appNameRegexSubstring, !(window.app.name ?? "").contains(regex) {
            return false
        }
        if let workspace = matcher.workspace, workspace != window.nodeWorkspace?.name {
            return false
        }
        return true
    }
}
