import AppKit

@MainActor
func currentWindowSurfaceDestination(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if let selfTabDestination = selfTabGroupSurfaceDestination(
        sourceWindow: sourceWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    ) {
        return selfTabDestination
    }

    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    if shouldSuppressSelfGroupSurfaceTarget(
        sourceNode: sourceNode,
        targetWorkspace: targetWorkspace,
        mouseLocation: mouseLocation,
        subject: subject,
        sourceWindow: sourceWindow,
    ) {
        return nil
    }
    guard let targetWindow = mouseLocation.findWindowDragTarget(in: targetWorkspace.rootTilingContainer, excluding: sourceNode) else {
        logWindowDragHitTestIfNeeded(
            signature: "surface:none:source=\(sourceWindow.windowId):subject=\(debugDescribe(subject))",
            "windowDragTarget.none source=\(debugDescribe(sourceWindow)) subject=\(debugDescribe(subject)) mouse=\(debugDescribe(mouseLocation)) workspace=\(targetWorkspace.name)"
        )
        return nil
    }
    logWindowDragHitTestIfNeeded(
        signature: "surface:target=\(targetWindow.windowId):source=\(sourceWindow.windowId):subject=\(debugDescribe(subject))",
        "windowDragTarget.surface source=\(debugDescribe(sourceWindow)) subject=\(debugDescribe(subject)) mouse=\(debugDescribe(mouseLocation)) target=\(debugDescribe(targetWindow))"
    )
    return windowSurfaceDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    )
}

@MainActor
private func selfTabGroupSurfaceDestination(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    guard subject == .window,
          detachOrigin == .tabStrip,
          let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .tabGroup,
          sourceParent.windowDragVisibleRect?.contains(mouseLocation) == true
    else { return nil }
    let targetWindow =
        sourceParent.tabActiveWindow ??
        sourceParent.mostRecentWindowRecursive ??
        sourceParent.anyLeafWindowRecursive ??
        sourceWindow
    logWindowDragHitTestIfNeeded(
        signature: "surface:self-tab-group-direct:source=\(sourceWindow.windowId)",
        "windowDragTarget.selfTabGroupDirect source=\(debugDescribe(sourceWindow)) mouse=\(debugDescribe(mouseLocation)) target=\(debugDescribe(targetWindow)) container=\(debugDescribe(sourceParent))"
    )
    return windowSurfaceDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    )
}

@MainActor
private func shouldSuppressSelfGroupSurfaceTarget(
    sourceNode: TreeNode,
    targetWorkspace: Workspace,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    sourceWindow: Window,
) -> Bool {
    guard subject == .group,
          let sourceWorkspace = sourceNode.nodeWorkspace,
          sourceWorkspace === targetWorkspace,
          sourceNode.windowDragVisibleRect?.contains(mouseLocation) == true
    else { return false }
    logWindowDragHitTestIfNeeded(
        signature: "surface:self-group:source=\(sourceWindow.windowId)",
        "windowDragTarget.selfGroup source=\(debugDescribe(sourceWindow)) mouse=\(debugDescribe(mouseLocation)) sourceNode=\(debugDescribe(sourceNode))"
    )
    return true
}
