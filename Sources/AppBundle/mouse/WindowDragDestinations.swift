import AppKit

@MainActor
func windowSurfaceDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    let targetNode = dragIntentTargetNode(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: subject,
        detachOrigin: detachOrigin,
    )
    if let reentryDestination = selfTabGroupTabReentryDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    ) {
        return reentryDestination
    }
    guard config.enableWindowManagement else {
        return legacyTabStackDestination(
            sourceWindow: sourceWindow,
            targetWindow: targetWindow,
            mouseLocation: mouseLocation,
            subject: subject,
            detachOrigin: detachOrigin,
        )
    }

    let resolvedIntent = resolveWindowDropIntent(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        targetNode: targetNode,
        mouseLocation: mouseLocation,
    )
    if detachOrigin == .tabStrip,
       subject == .window,
       let sourceParent = sourceWindow.parent as? TilingContainer,
       sourceParent.layout == .tabGroup,
       targetWindow.parent === sourceParent
    {
        logWindowDragHitTestIfNeeded(
            signature: "self-tab-group-intent:source=\(sourceWindow.windowId):target=\(targetWindow.windowId):intent=\(resolvedIntent?.intent.zone.rawValue ?? "nil")",
            "windowDragTarget.selfTabGroupIntent mouse=\(debugDescribe(mouseLocation)) source=\(debugDescribe(sourceWindow)) target=\(debugDescribe(targetWindow)) targetNode=\(debugDescribe(targetNode)) visible=\(debugDescribe(targetNode.windowDragVisibleRect)) resolved=\(resolvedIntent?.intent.zone.rawValue ?? "nil")"
        )
    }

    guard let resolvedIntent else { return nil }
    return destinationFromWindowDropIntent(
        resolvedIntent,
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    )
}

@MainActor
private func legacyTabStackDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    guard subject == .window,
          config.windowTabs.enabled,
          let tabDestination = tabStackDestination(targetWindow: targetWindow, mouseLocation: mouseLocation)
    else { return nil }

    if case .tabStack(let targetWindowId) = tabDestination.kind,
       let targetWindow = Window.get(byId: targetWindowId),
       shouldSuppressSameTabGroupTabDestination(
           sourceWindow: sourceWindow,
           targetWindow: targetWindow,
           detachOrigin: detachOrigin,
       )
    {
        return nil
    }
    return tabDestination
}
