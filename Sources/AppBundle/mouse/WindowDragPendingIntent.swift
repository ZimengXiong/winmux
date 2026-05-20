import AppKit
import Common

@MainActor
func updatePendingWindowDragIntent(sourceWindow: Window, mouseLocation: CGPoint) -> Bool {
    updatePendingWindowDragIntent(sourceWindow: sourceWindow, mouseLocation: mouseLocation, subject: .window, detachOrigin: .window)
}

@MainActor
func updatePendingWindowDragIntent(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> Bool {
    if detachOrigin != .tabStrip {
        WindowDragCursorProxyPanel.shared.hide()
    }

    guard let destination = currentWindowDragIntentDestination(
        sourceWindow: sourceWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    ) else {
        logWindowDragIntentIfNeeded(
            signature: "drag-live:no-destination:source=\(sourceWindow.windowId):subject=\(debugDescribe(subject)):origin=\(detachOrigin):bucket=\(debugDescribeDragPointBucket(mouseLocation))",
            "[drag-live] destination none source=\(sourceWindow.windowId) subject=\(debugDescribe(subject)) origin=\(detachOrigin) mouse=\(debugDescribe(mouseLocation)) bucket=\(debugDescribeDragPointBucket(mouseLocation)); clearing previews"
        )
        updateSidebarDragFeedback(sourceWindow: sourceWindow, subject: subject, destination: nil)
        clearPendingWindowDragIntent()
        if detachOrigin == .tabStrip {
            showWorkspaceSidebarDragCursorPreview(sourceWindow: sourceWindow, subject: subject, point: mouseLocation)
        }
        return false
    }
    updateSidebarDragFeedback(sourceWindow: sourceWindow, subject: subject, destination: destination)
    if detachOrigin == .tabStrip {
        showWorkspaceSidebarDragCursorPreview(sourceWindow: sourceWindow, subject: subject, point: mouseLocation)
    }
    return setPendingWindowDragIntent(
        sourceWindowId: sourceWindow.windowId,
        sourceSubject: subject,
        detachOrigin: detachOrigin,
        destination: destination,
    )
}

@MainActor
func updatePendingDetachedTabIntent(sourceWindow: Window, mouseLocation: CGPoint, origin: TabDetachOrigin) -> Bool {
    updatePendingWindowDragIntent(sourceWindow: sourceWindow, mouseLocation: mouseLocation, subject: .window, detachOrigin: origin)
}

@MainActor
func refreshPendingWindowDragIntentFromGlobalMouseDrag() {
    WorkspaceSidebarPanel.refreshAll()
    guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .move else {
        clearPendingWindowDragIntent()
        return
    }
    guard let windowId = currentlyManipulatedWithMouseWindowId,
          Window.get(byId: windowId) != nil
    else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    WindowMouseInteractionDriver.shared.noteGlobalDragActivity()
}

@MainActor
func setPendingWindowDragIntent(
    sourceWindowId: UInt32,
    sourceSubject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    destination: WindowDragIntentDestination,
) -> Bool {
    let isPointerSettled = WindowDragFrameGate.shared.state(for: sourceWindowId)?.isSettled ?? false
    syncTargetTabGroupChromeForDropIntentOverlay(
        destination.kind,
        detachOrigin: detachOrigin,
        hasOverlay: destination.dropIntentOverlay != nil,
    )
    if let pendingWindowDragIntent,
       pendingWindowDragIntent.sourceWindowId == sourceWindowId,
       pendingWindowDragIntent.sourceSubject == sourceSubject,
       pendingWindowDragIntent.kind == destination.kind,
       pendingWindowDragIntent.title == destination.title,
       pendingWindowDragIntent.subtitle == destination.subtitle,
       pendingWindowDragIntent.previewStyle == destination.previewStyle,
       pendingWindowDragIntent.previewGeometry == destination.previewGeometry,
       pendingWindowDragIntent.isGroup == destination.isGroup,
       pendingWindowDragIntent.previewRect.isEqual(to: destination.previewRect),
       pendingWindowDragIntent.interactionRect.isEqual(to: destination.interactionRect)
    {
        return true
    }

    let previousIntent = pendingWindowDragIntent
    pendingWindowDragIntent = PendingWindowDragIntent(
        sourceWindowId: sourceWindowId,
        sourceSubject: sourceSubject,
        kind: destination.kind,
        previewRect: destination.previewRect,
        interactionRect: destination.interactionRect,
        title: destination.title,
        subtitle: destination.subtitle,
        previewStyle: destination.previewStyle,
        previewGeometry: destination.previewGeometry,
        isGroup: destination.isGroup,
        isPointerSettled: isPointerSettled,
    )
    let signature =
        "intent:source=\(sourceWindowId):subject=\(debugDescribe(sourceSubject)):kind=\(debugDescribe(destination.kind)):preview=\(debugDescribe(destination.previewRect)):interaction=\(debugDescribe(destination.interactionRect))"
    logWindowDragIntentIfNeeded(
        signature: signature,
        "windowDragIntent.update mouse=\(debugDescribe(mouseLocation)) source=\(debugDescribe(Window.get(byId: sourceWindowId))) subject=\(debugDescribe(sourceSubject)) prevKind=\(previousIntent.map { debugDescribe($0.kind) } ?? "nil") prevPreview=\(debugDescribe(previousIntent?.previewRect)) newKind=\(debugDescribe(destination.kind)) newPreview=\(debugDescribe(destination.previewRect)) newInteraction=\(debugDescribe(destination.interactionRect)) style=\(destination.previewStyle) geometry=\(destination.previewGeometry)"
    )
    if let overlay = destination.dropIntentOverlay {
        let activeZone = overlay.activeZone?.rawValue ?? "nil"
        logWindowDragIntentIfNeeded(
            signature: "drag-live:overlay-show:source=\(sourceWindowId):kind=\(debugDescribe(destination.kind)):bucket=\(debugDescribeDragPointBucket(mouseLocation)):zone=\(activeZone)",
            "[drag-live] overlay show request source=\(sourceWindowId) kind=\(debugDescribe(destination.kind)) zone=\(activeZone) target=\(debugDescribe(overlay.targetFrame)) mouse=\(debugDescribe(mouseLocation)) bucket=\(debugDescribeDragPointBucket(mouseLocation))"
        )
        WindowDropIntentOverlayPanelController.shared.show(overlay)
    } else {
        logWindowDragIntentIfNeeded(
            signature: "drag-live:overlay-hide:source=\(sourceWindowId):kind=\(debugDescribe(destination.kind)):bucket=\(debugDescribeDragPointBucket(mouseLocation))",
            "[drag-live] overlay hide request source=\(sourceWindowId) kind=\(debugDescribe(destination.kind)) reason=destination-has-no-overlay mouse=\(debugDescribe(mouseLocation)) bucket=\(debugDescribeDragPointBucket(mouseLocation))"
        )
        WindowDropIntentOverlayPanelController.shared.hide()
    }
    return true
}

@MainActor
func clearPendingWindowDragIntent() {
    if let pendingWindowDragIntent {
        logWindowDragIntentIfNeeded(
            signature: "intent-cleared:source=\(pendingWindowDragIntent.sourceWindowId):kind=\(debugDescribe(pendingWindowDragIntent.kind))",
            "windowDragIntent.clear mouse=\(debugDescribe(mouseLocation)) source=\(debugDescribe(Window.get(byId: pendingWindowDragIntent.sourceWindowId))) kind=\(debugDescribe(pendingWindowDragIntent.kind)) preview=\(debugDescribe(pendingWindowDragIntent.previewRect))"
        )
    }
    pendingWindowDragIntent = nil
    lastWindowDragIntentLogSignature = nil
    setPinnedDraggedWindowId(nil)
    setWorkspaceSidebarDropPreviewIfChanged(nil)
    WindowDropIntentOverlayPanelController.shared.hide()
    WindowTabStripPanelController.shared.clearHiddenPassiveTabGroupChrome()
    WindowDragCursorProxyPanel.shared.hide()
    if getCurrentMouseManipulationKind() == .resize, isLeftMouseButtonDown {
        logWindowDragLive("dragIntent.clear preserving resizePreview during active resize manipulated=\(currentlyManipulatedWithMouseWindowId?.description ?? "nil")")
    } else {
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "dragIntent.clear")
    }
}

@MainActor
private func syncTargetTabGroupChromeForDropIntentOverlay(
    _ kind: WindowDragIntentKind,
    detachOrigin: TabDetachOrigin,
    hasOverlay: Bool,
) {
    guard hasOverlay,
          detachOrigin != .tabStrip,
          let targetWindow = targetWindowForDropIntent(kind),
          let tabGroup = targetWindow.nearestWindowTabGroup,
          tabGroup.usesWindowTabBehavior
    else {
        WindowTabStripPanelController.shared.clearHiddenPassiveTabGroupChrome()
        return
    }
    WindowTabStripPanelController.shared.setHiddenPassiveTabGroupChrome([ObjectIdentifier(tabGroup)])
}

@MainActor
private func targetWindowForDropIntent(_ kind: WindowDragIntentKind) -> Window? {
    switch kind {
        case .tabStack(let targetWindowId),
             .stackSplit(let targetWindowId, _),
             .swap(let targetWindowId):
            Window.get(byId: targetWindowId)
        case .detachTab, .moveToWorkspace, .moveToWorkspaceZone, .createWorkspace, .sidebarHover:
            nil
    }
}

@MainActor
func applyPendingWindowDragIntentIfPossible() -> Bool {
    defer { clearPendingWindowDragIntent() }
    let currentMouseLocation = MousePointerTracker.shared.currentSample.point
    guard let pendingWindowDragIntent,
          let sourceWindow = Window.get(byId: pendingWindowDragIntent.sourceWindowId),
          pendingWindowDragIntent.interactionRect.contains(currentMouseLocation),
          isWindowDragIntentKindEnabled(pendingWindowDragIntent.kind)
    else { return false }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: pendingWindowDragIntent.sourceSubject)
    switch pendingWindowDragIntent.kind {
        case .tabStack(let targetWindowId):
            guard pendingWindowDragIntent.sourceSubject == .window else { return false }
            guard let targetWindow = Window.get(byId: targetWindowId),
                  sourceWindow != targetWindow
            else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId, targetWindow.windowId])
            createOrAppendWindowTabStack(sourceWindow: sourceWindow, onto: targetWindow)
            return true
        case .detachTab(let windowId):
            guard sourceWindow.windowId == windowId else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId])
            return removeWindowFromTabStack(sourceWindow)
        case .stackSplit(let targetWindowId, let position):
            guard let targetWindow = Window.get(byId: targetWindowId)
            else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId, targetWindow.windowId])
            return applyWindowStackSplitDragIntent(
                sourceWindow: sourceWindow,
                sourceSubject: pendingWindowDragIntent.sourceSubject,
                targetWindow: targetWindow,
                position: position,
            )
        case .swap(let targetWindowId):
            guard let targetWindow = Window.get(byId: targetWindowId)
            else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId, targetWindow.windowId])
            return applyWindowSwapDragIntent(
                sourceWindow: sourceWindow,
                sourceSubject: pendingWindowDragIntent.sourceSubject,
                targetWindow: targetWindow,
            )
        case .moveToWorkspace(let workspaceName):
            guard let targetWorkspace = Workspace.existing(byName: workspaceName) else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId])
            if pendingWindowDragIntent.previewStyle == .sidebarWorkspaceMove {
                applySidebarWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, targetWorkspace: targetWorkspace)
            } else {
                applyWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, mouseLocation: mouseLocation, targetWorkspace: targetWorkspace)
            }
            return true
        case .moveToWorkspaceZone(let workspaceName, let zone):
            guard let targetWorkspace = Workspace.existing(byName: workspaceName) else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId])
            applyWorkspaceZoneMove(sourceNode: sourceNode, sourceWindow: sourceWindow, targetWorkspace: targetWorkspace, zone: zone)
            return true
        case .createWorkspace:
            syncClosedWindowsCacheToCurrentWorld()
            suppressPostDragAxObserverEvents(for: [sourceWindow.windowId])
            return createWorkspaceFromSidebarDrag(sourceNode: sourceNode, sourceWindow: sourceWindow)
        case .sidebarHover:
            return false
    }
}
