import AppKit
import Common

final class MacWindow: Window {
    let macApp: MacApp
    private var prevUnhiddenProportionalPositionInsideWorkspaceRect: CGPoint?
    private var hiddenInCorner: OptimalHideCorner?

    @MainActor
    private init(_ id: UInt32, _ actor: MacApp, lastFloatingSize: CGSize?, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) {
        self.macApp = actor
        super.init(id: id, actor, lastFloatingSize: lastFloatingSize, parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor static var allWindowsMap: [UInt32: MacWindow] = [:]
    @MainActor static var allWindows: [MacWindow] { Array(allWindowsMap.values) }

    @MainActor
    @discardableResult
    static func getOrRegister(windowId: UInt32, macApp: MacApp) async throws -> MacWindow? {
        if let existing = allWindowsMap[windowId] {
            _ = try await existing.getAxRect()
            return existing
        }
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
        window.lastKnownActualRect = rect
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
        let refreshSnapshotCloseFallback = refreshSnapshot?.fallbackWhenFocusedWindowCloses?.liveOrNil
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

    @MainActor
    func requestCloseForProjectDeletion(timeout: TimeInterval = 1.5) async -> Bool {
        guard (try? await macApp.pressCloseButton(windowId)) == true else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await macApp.containsAxWindow(windowId)) == false {
                garbageCollect(skipClosedWindowsCache: true)
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    override func closeAxWindow() {
        garbageCollect(skipClosedWindowsCache: true)
        macApp.closeAndUnregisterAxWindow(windowId)
    }

    // todo it's part of the window layout and should be moved to layoutRecursive.swift
    @MainActor
    func hideInCorner(_ corner: OptimalHideCorner) async throws {
        if isHiddenInCorner, hiddenInCorner == corner {
            return
        }
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
                // Zoom will jump off if you do one pixel offset https://github.com/nikitabobko/WinMux/issues/527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.appId == .zoom ? .zero : CGPoint(x: 1, y: -1)
                p = nodeMonitor.visibleRect.bottomLeftCorner + onePixelOffset + CGPoint(x: -s.width, y: 0)
            case .bottomRightCorner:
                // Zoom will jump off if you do one pixel offset https://github.com/nikitabobko/WinMux/issues/527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.appId == .zoom ? .zero : CGPoint(x: 1, y: 1)
                p = nodeMonitor.visibleRect.bottomRightCorner - onePixelOffset
        }
        setAxFrame(p, nil)
        hiddenInCorner = corner
    }

    @MainActor
    func unhideFromCorner() {
        guard let prevUnhiddenProportionalPositionInsideWorkspaceRect else { return }
        guard let nodeWorkspace else { return } // hiding only makes sense for workspace windows
        guard let parent else { return }

        func restoreToSavedWorkspacePosition() {
            let workspaceRect = nodeWorkspace.workspaceMonitor.rect
            var newX = workspaceRect.topLeftX + workspaceRect.width * prevUnhiddenProportionalPositionInsideWorkspaceRect.x
            var newY = workspaceRect.topLeftY + workspaceRect.height * prevUnhiddenProportionalPositionInsideWorkspaceRect.y
            let windowWidth = lastKnownActualRect?.width ?? lastFloatingSize?.width ?? 0
            let windowHeight = lastKnownActualRect?.height ?? lastFloatingSize?.height ?? 0
            newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
            newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))
            setAxFrame(CGPoint(x: newX, y: newY), nil)
        }

        switch getChildParentRelation(child: self, parent: parent) {
            // Just a small optimization to avoid unnecessary AX calls for non floating windows
            // Tiling windows should be unhidden with layoutRecursive anyway
            case .floatingWindow:
                restoreToSavedWorkspacePosition()
            case .macosNativeFullscreenWindow, .macosNativeHiddenAppWindow, .macosNativeMinimizedWindow,
                 .macosPopupWindow, .tiling, .rootTilingContainer, .shimContainerRelation: break
        }

        self.prevUnhiddenProportionalPositionInsideWorkspaceRect = nil
        self.hiddenInCorner = nil
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
        let rect = try await macApp.getAxRect(windowId)
        let windowId = self.windowId
        await MainActor.run {
            Window.get(byId: windowId)?.lastKnownActualRect = rect
        }
        return rect
    }
}
