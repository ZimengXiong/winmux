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
    if subject == .window,
       config.windowTabs.enabled,
       let tabDestination = tabStackDestination(targetWindow: targetWindow, mouseLocation: mouseLocation)
    {
        if case .tabStack(let targetWindowId) = tabDestination.kind,
           let targetWindow = Window.get(byId: targetWindowId),
           shouldSuppressSameTabGroupTabDestination(
               sourceWindow: sourceWindow,
               targetWindow: targetWindow,
               detachOrigin: detachOrigin,
           )
        {
            // Body drags from an existing tab group should be able to detach instead of
            // being trapped by that same group's own tab insert target.
        } else {
            return tabDestination
        }
    }

    guard config.enableWindowManagement else {
        return nil
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
