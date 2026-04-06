import AppKit
import Common

@MainActor
private var moveWithMouseTask: Task<(), any Error>? = nil

func movedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let windowId = ax.containingWindowId()
    let notif = notif as String
    Task { @MainActor in
        if shouldIgnoreMovedObsForCurrentDragSession(windowId: windowId) ||
            shouldIgnoreAxObserverEventForPostDragSuppression(windowId: windowId, notif: notif)
        {
            return
        }
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        guard let windowId, let window = Window.get(byId: windowId), try await isManipulatedWithMouse(window) else {
            scheduleRefreshSession(.ax(notif))
            return
        }
        moveWithMouseTask?.cancel()
        moveWithMouseTask = Task {
            try checkCancellation()
            try await runLightSession(.ax(notif), token) {
                try await moveWithMouse(window)
            }
        }
    }
}

@MainActor
private func moveWithMouse(_ window: Window) async throws { // todo cover with tests
    if !config.enableWindowManagement {
        let subject = resolvedMouseDragSubject(for: window)
        let nativeAnchorRect = try await window.getAxRect()
        let anchorRect =
            resolvedDraggedWindowAnchorRect(for: window, subject: subject) ??
            nativeAnchorRect ??
            window.lastKnownActualRect ??
            window.lastAppliedLayoutPhysicalRect
        _ = beginWindowMoveWithMouseSessionIfNeeded(
            windowId: window.windowId,
            subject: subject,
            detachOrigin: .window,
            startedInSidebar: false,
            anchorRect: anchorRect,
        )
        let mouseLocation = mouseLocation
        let didUpdateIntent = updatePendingWindowDragIntent(
            sourceWindow: window,
            mouseLocation: mouseLocation,
            subject: subject,
            detachOrigin: .window,
        )
        if didUpdateIntent {
            clearPendingUnmanagedWindowSnap()
        } else if subject == .window {
            refreshPendingUnmanagedWindowSnap(sourceWindow: window, mouseLocation: mouseLocation)
        } else {
            clearPendingUnmanagedWindowSnap()
        }
        return
    }
    syncClosedWindowsCacheToCurrentWorld()
    guard let parent = window.parent else { return }
    switch parent.cases {
        case .workspace:
            try await moveFloatingWindow(window)
        case .tilingContainer:
            moveTilingWindow(window)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return // Unconventional windows can't be moved with mouse
    }
}

@MainActor
private func moveFloatingWindow(_ window: Window) async throws {
    guard let targetWorkspace = try await window.getCenter()?.monitorApproximation.activeWorkspace else { return }
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
    )
    if didStartSession, subject == .window {
        window.lastAppliedLayoutPhysicalRect = nil
    }
    let mouseLocation = mouseLocation
    _ = updatePendingWindowDragIntent(
        sourceWindow: window,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: .window,
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
            case .accordion:
                tree.mostRecentChild
        }
        guard let target else { return nil }
        return switch target.tilingTreeNodeCasesOrDie() {
            case .window(let window): window
            case .tilingContainer(let container): findIn(tree: container, virtual: virtual)
        }
    }
}
