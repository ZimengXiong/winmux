import AppKit
import Common

@MainActor private var moveWithMouseSessionWindowIdsInFlight: Set<UInt32> = []
@MainActor private var moveWithMouseTrailingRerunWindowIds: Set<UInt32> = []

func movedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let windowId = ax.containingWindowId()
    let notif = notif as String
    Task { @MainActor in
        await handleMovedEvent(windowId: windowId, notif: notif)
    }
}

@MainActor
private func handleMovedEvent(windowId: UInt32?, notif: String) async {
    if shouldIgnoreMovedObsForCurrentDragSession(windowId: windowId) ||
        WindowMouseInteractionOpacityController.shared.shouldSuppressObserverEvent(windowId: windowId) ||
        shouldIgnoreAxObserverEventForPostDragSuppression(windowId: windowId, notif: notif)
    {
        // Suppressed events are our own parking/restore/post-drag moves: their authors write
        // the resulting rect into the cache themselves, so invalidating here would wipe
        // deliberately recorded values.
        return
    }
    // The cached native state (rect, fullscreen) is stale the moment the window reports
    // movement. Consumers fall back to an on-demand AX fetch (or the last applied layout
    // rect), so invalidating keeps the caches honest without polling every window on every
    // refresh barrier.
    if let windowId {
        Window.get(byId: windowId)?.invalidateLastKnownNativeState()
    }
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    guard let windowId, let window = Window.get(byId: windowId) else {
        scheduleRefreshSession(.ax(notif))
        return
    }
    if isContinuingManagedDragSessionForMovedEvent(window) { return }
    // Coalesce: kAXMoved arrives per frame during drags, and each session reads the mouse
    // and window state fresh when it runs, so events arriving while a session for this
    // window is queued or running add no information — they only pile up main-actor work
    // that keeps running long after the drag under CPU load. The trailing-rerun mark
    // guarantees the burst's final position is still processed once the session finishes
    // (a floating drag's workspace rebind depends on the last event).
    if moveWithMouseSessionWindowIdsInFlight.contains(windowId) {
        moveWithMouseTrailingRerunWindowIds.insert(windowId)
        return
    }
    // Reserve before the isManipulatedWithMouse suspension point: two queued events for the
    // same window must not both pass the in-flight check and spawn concurrent sessions.
    moveWithMouseSessionWindowIdsInFlight.insert(windowId)
    guard (try? await isManipulatedWithMouse(window)) == true else {
        moveWithMouseSessionWindowIdsInFlight.remove(windowId)
        moveWithMouseTrailingRerunWindowIds.remove(windowId)
        scheduleRefreshSession(.ax(notif))
        return
    }
    Task {
        defer {
            moveWithMouseSessionWindowIdsInFlight.remove(windowId)
            if moveWithMouseTrailingRerunWindowIds.remove(windowId) != nil {
                Task { @MainActor in
                    await handleMovedEvent(windowId: windowId, notif: notif)
                }
            }
        }
        do {
            try checkCancellation()
            try await runLightSession(.ax(notif), token) {
                try await moveWithMouse(window)
            }
        } catch is CancellationError {
            // A newer interaction/session superseded this coalesced event.
        } catch {
            debugFocusLog("moveWithMouse coalesced session failed windowId=\(windowId) error=\(error)")
        }
    }
}

@MainActor
private func moveWithMouse(_ window: Window) async throws { // todo cover with tests
    syncClosedWindowsCacheToCurrentWorld()
    guard let parent = window.parent else { return }
    switch parent.cases {
        case .workspace:
            moveFloatingWindowWithMouse(window)
        case .tilingContainer:
            moveTilingWindow(window)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return // Unconventional windows can't be moved with mouse
    }
}

@MainActor
func moveFloatingWindowWithMouse(_ window: Window) {
    if WindowMouseInteractionDriver.shared.moveSession?.windowId != window.windowId {
        let subject = resolvedMouseDragSubject(for: window)
        _ = beginWindowMoveWithMouseSessionIfNeeded(
            windowId: window.windowId,
            subject: subject,
            detachOrigin: .window,
            startedInSidebar: false,
            anchorRect: window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect,
            refreshActualRects: false,
        )
        WindowMouseInteractionDriver.shared.startMove(
            windowId: window.windowId,
            subject: subject,
            detachOrigin: .window,
            startedInSidebar: false,
        )
    }
    let targetWorkspace = MousePointerTracker.shared.currentSample.point.monitorApproximation.activeWorkspace
    guard let parent = window.parent else { return }
    if targetWorkspace != parent {
        window.bindAsFloatingWindow(to: targetWorkspace)
    }
}

@MainActor
private func moveTilingWindow(_ window: Window) {
    let subject = resolvedMouseDragSubject(for: window)
    let didStartSession = beginWindowMoveWithMouseSessionIfNeeded(
        windowId: window.windowId,
        subject: subject,
        detachOrigin: .window,
        startedInSidebar: false,
        anchorRect: resolvedDraggedWindowAnchorRect(for: window, subject: subject),
        refreshActualRects: subject == .window,
    )
    if didStartSession, subject == .window {
        window.lastAppliedLayoutPhysicalRect = nil
    }
    WindowMouseInteractionDriver.shared.startMove(
        windowId: window.windowId,
        subject: subject,
        detachOrigin: .window,
        startedInSidebar: false,
    )
}

@MainActor
func swapWindows(_ window1: Window, _ window2: Window) {
    swapNodes(window1.moveNode, window2.moveNode)
}

@MainActor
func swapNodes(_ node1: TreeNode, _ node2: TreeNode) {
    if node1 == node2 { return }
    guard let index1 = node1.ownIndex else { return }
    guard let index2 = node2.ownIndex else { return }

    if index1 < index2 {
        let binding2 = node2.unbindFromParent()
        let binding1 = node1.unbindFromParent()

        node2.bind(to: binding1.parent, adaptiveWeight: binding1.adaptiveWeight, index: binding1.index)
        node1.bind(to: binding2.parent, adaptiveWeight: binding2.adaptiveWeight, index: binding2.index)
    } else {
        let binding1 = node1.unbindFromParent()
        let binding2 = node2.unbindFromParent()

        node1.bind(to: binding2.parent, adaptiveWeight: binding2.adaptiveWeight, index: binding2.index)
        node2.bind(to: binding1.parent, adaptiveWeight: binding1.adaptiveWeight, index: binding1.index)
    }
    node1.markAsMostRecentChild()
}

extension CGPoint {
    @MainActor
    func findIn(tree: TilingContainer, virtual: Bool) -> Window? {
        let point = self
        let target: TreeNode? = switch tree.layout {
            case .tiles:
                tree.children.first(where: {
                    (virtual ? $0.lastAppliedLayoutVirtualRect : $0.lastAppliedLayoutPhysicalRect)?.contains(point) == true
                })
            case .tabGroup:
                tree.mostRecentChild
        }
        guard let target else { return nil }
        return switch target.tilingTreeNodeCasesOrDie() {
            case .window(let window): window
            case .tilingContainer(let container): findIn(tree: container, virtual: virtual)
        }
    }
}
