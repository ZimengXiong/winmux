import AppKit
import Common

@MainActor
func pinnedDraggedWindowRect(for sourceWindow: Window, subject: WindowDragSubject, fallbackAnchorRect: Rect) -> Rect {
    switch subject {
        case .window:
            return fallbackAnchorRect
        case .group:
            return resolvedDraggedWindowAnchorRect(for: sourceWindow, subject: .window) ?? fallbackAnchorRect
    }
}

@MainActor
func setWorkspaceSidebarDropPreviewIfChanged(_ preview: WorkspaceSidebarDropPreviewViewModel?) {
    if TrayMenuModel.shared.workspaceSidebarDropPreview != preview {
        TrayMenuModel.shared.workspaceSidebarDropPreview = preview
    }
}

@MainActor
func tabStackDestination(targetWindow: Window, mouseLocation: CGPoint? = nil) -> WindowDragIntentDestination? {
    guard isWindowDragIntentKindEnabled(.tabStack(targetWindowId: targetWindow.windowId)),
          let rects = targetWindow.tabStackTargetRects,
          mouseLocation.map(rects.interactionRect.contains) ?? true
    else { return nil }
    return WindowDragIntentDestination(
        kind: .tabStack(targetWindowId: targetWindow.windowId),
        previewContainerRect: rects.containerRect,
        previewRect: rects.previewRect,
        interactionRect: rects.interactionRect,
        title: "Insert Into Tabs",
        subtitle: "Drop near the top edge to add this window",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
    )
}

@MainActor
func selfTabGroupTabReentryDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    guard subject == .window,
          detachOrigin == .tabStrip,
          config.windowTabs.enabled,
          let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .tabGroup,
          targetWindow.parent === sourceParent,
          let previewRect = sourceParent.windowTabDropZoneRect,
          let interactionRect = sourceParent.windowTabDropInteractionRect,
          interactionRect.contains(mouseLocation)
    else { return nil }

    return WindowDragIntentDestination(
        kind: .tabStack(targetWindowId: targetWindow.windowId),
        previewContainerRect: sourceParent.windowDragVisibleRect ?? previewRect,
        previewRect: previewRect,
        interactionRect: interactionRect,
        title: "Return To Tabs",
        subtitle: "Drop to cancel the detach and put this tab back in the group",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
    )
}

@MainActor
func swapDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint? = nil,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if shouldSuppressSameTabGroupSwapDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: subject,
        detachOrigin: detachOrigin
    ) {
        return nil
    }
    if shouldSuppressSwapDestination(sourceWindow: sourceWindow, subject: subject) {
        return nil
    }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetNode = dragIntentTargetNode(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: subject,
        detachOrigin: detachOrigin,
    )
    guard !isBlockedByDragTargetContainment(sourceNode: sourceNode, targetNode: targetNode),
          !isInvalidGroupSelfTarget(sourceNode: sourceNode, targetNode: targetNode, subject: subject),
          let previewRect = targetNode.swapDropZoneRect
    else { return nil }
    let interactionRect = if subject == .group {
        previewRect.expanded(left: 4, right: 4, top: 4, bottom: 6)
    } else {
        previewRect.expanded(left: 10, right: 10, top: 10, bottom: 10)
    }
    guard mouseLocation.map(interactionRect.contains) ?? true else { return nil }
    let isTabGroup = targetNode is TilingContainer
    return WindowDragIntentDestination(
        kind: .swap(targetWindowId: targetWindow.windowId),
        previewContainerRect: targetNode.windowDragVisibleRect ?? previewRect,
        previewRect: previewRect,
        interactionRect: interactionRect,
        title: isTabGroup ? "Swap With Tab Group" : "Swap Positions",
        subtitle: isTabGroup ? "Drop in the body to move around the whole group" : "Drop in the body to swap these windows",
        previewStyle: .swap,
        previewGeometry: .rounded,
        isGroup: subject == .group,
    )
}

@MainActor
func stackSplitDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint? = nil,
    subject: WindowDragSubject,
    position: WindowStackSplitPosition,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if shouldSuppressSwapDestination(sourceWindow: sourceWindow, subject: subject) {
        return nil
    }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetNode = dragIntentTargetNode(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: subject,
        detachOrigin: detachOrigin,
    )
    guard !isBlockedByDragTargetContainment(sourceNode: sourceNode, targetNode: targetNode),
          !isInvalidGroupSelfTarget(sourceNode: sourceNode, targetNode: targetNode, subject: subject),
          canOfferWindowStackSplit(sourceNode: sourceNode, targetNode: targetNode, position: position),
          let preview = resolvedWindowStackSplitPreview(targetNode: targetNode, position: position),
          let interactionRect = targetNode.stackSplitDropZoneRect(position: position)?
          .expanded(left: subject == .group ? 4 : 10, right: subject == .group ? 4 : 10, top: 0, bottom: 0)
    else { return nil }
    guard mouseLocation.map(interactionRect.contains) ?? true else { return nil }
    return WindowDragIntentDestination(
        kind: .stackSplit(targetWindowId: targetWindow.windowId, position: position),
        previewContainerRect: targetNode.windowDragVisibleRect ?? preview.rect,
        previewRect: preview.rect,
        interactionRect: interactionRect,
        title: position.title,
        subtitle: position.subtitle,
        previewStyle: .stackSplit,
        previewGeometry: preview.geometry,
        isGroup: subject == .group,
    )
}

@MainActor
func windowSurfacePreviewZones(
    sourceWindow: Window,
    targetWindow: Window,
    targetNode: TreeNode,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    activeKind: WindowDragIntentKind,
) -> [WindowDragIntentPreviewZone] {
    var zones: [WindowDragIntentPreviewZone] = []

    if subject == .window,
       config.windowTabs.enabled,
       let tabDestination = tabStackDestination(targetWindow: targetWindow),
       !shouldSuppressSameTabGroupTabDestination(
           sourceWindow: sourceWindow,
           targetWindow: targetWindow,
           detachOrigin: detachOrigin,
       )
    {
        zones.append(WindowDragIntentPreviewZone(
            rect: tabDestination.previewRect,
            style: .tabInsert,
            geometry: .tabStrip,
            isActive: activeKind == tabDestination.kind,
        ))
    }

    guard config.enableWindowManagement else { return zones }

    for position in [WindowStackSplitPosition.left, .right, .above, .below] {
        guard let destination = stackSplitDestination(
            sourceWindow: sourceWindow,
            targetWindow: targetWindow,
            subject: subject,
            position: position,
            detachOrigin: detachOrigin,
        ) else { continue }
        zones.append(WindowDragIntentPreviewZone(
            rect: targetNode.stackSplitDropZoneRect(position: position) ?? destination.previewRect,
            style: .stackSplit,
            geometry: position.previewGeometry,
            isActive: activeKind == destination.kind,
        ))
    }

    if let destination = swapDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: subject,
        detachOrigin: detachOrigin,
    ) {
        zones.append(WindowDragIntentPreviewZone(
            rect: targetNode.swapDropZoneRect ?? destination.previewRect,
            style: .swap,
            geometry: .rounded,
            isActive: activeKind == destination.kind,
        ))
    }

    return zones
}

@MainActor
func currentWindowTabDropDestination(sourceWindow: Window, mouseLocation: CGPoint) -> WindowDragIntentDestination? {
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    return mouseLocation.findWindowTabDropDestination(in: targetWorkspace.rootTilingContainer, excluding: sourceWindow)
}

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

    let bodyIntent = targetNode.bodyDragIntent(at: mouseLocation)
    if detachOrigin == .tabStrip,
       subject == .window,
       let sourceParent = sourceWindow.parent as? TilingContainer,
       sourceParent.layout == .tabGroup,
       targetWindow.parent === sourceParent
    {
        logWindowDragHitTestIfNeeded(
            signature: "self-tab-group-intent:source=\(sourceWindow.windowId):target=\(targetWindow.windowId):intent=\(debugDescribe(bodyIntent))",
            "windowDragTarget.selfTabGroupIntent mouse=\(debugDescribe(mouseLocation)) source=\(debugDescribe(sourceWindow)) target=\(debugDescribe(targetWindow)) targetNode=\(debugDescribe(targetNode)) visible=\(debugDescribe(targetNode.windowDragVisibleRect)) swap=\(debugDescribe(targetNode.swapDropZoneRect)) left=\(debugDescribe(targetNode.stackSplitDropZoneRect(position: .left))) right=\(debugDescribe(targetNode.stackSplitDropZoneRect(position: .right))) above=\(debugDescribe(targetNode.stackSplitDropZoneRect(position: .above))) below=\(debugDescribe(targetNode.stackSplitDropZoneRect(position: .below))) resolved=\(debugDescribe(bodyIntent))"
        )
    }

    switch bodyIntent {
        case .stackSplit(let position):
            return stackSplitDestination(
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                position: position,
                detachOrigin: detachOrigin,
            )
        case .swap:
            return swapDestination(
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                detachOrigin: detachOrigin,
            )
        case nil:
            return nil
    }
}

@MainActor
func currentWindowSurfaceDestination(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if subject == .window,
       detachOrigin == .tabStrip,
       let sourceParent = sourceWindow.parent as? TilingContainer,
       sourceParent.layout == .tabGroup,
       sourceParent.windowDragVisibleRect?.contains(mouseLocation) == true
    {
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

    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    if subject == .group,
       let sourceWorkspace = sourceNode.nodeWorkspace,
       sourceWorkspace === targetWorkspace,
       sourceNode.windowDragVisibleRect?.contains(mouseLocation) == true
    {
        logWindowDragHitTestIfNeeded(
            signature: "surface:self-group:source=\(sourceWindow.windowId)",
            "windowDragTarget.selfGroup source=\(debugDescribe(sourceWindow)) mouse=\(debugDescribe(mouseLocation)) sourceNode=\(debugDescribe(sourceNode))"
        )
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
func stickyTargetWindow(for sticky: PendingWindowDragIntent) -> Window? {
    switch sticky.kind {
        case .tabStack(let targetWindowId), .stackSplit(let targetWindowId, _), .swap(let targetWindowId):
            Window.get(byId: targetWindowId)
        case .detachTab, .moveToWorkspace, .createWorkspace, .sidebarHover:
            nil
    }
}

@MainActor
func stickyTargetTrackingRect(targetWindow: Window, previewStyle: WindowTabDropPreviewStyle) -> Rect? {
    switch previewStyle {
        case .tabInsert:
            targetWindow.windowDragVisibleRect?.expanded(
                left: windowTabInsertStickyTrackingHorizontalInset,
                right: windowTabInsertStickyTrackingHorizontalInset,
                top: windowTabInsertStickyTrackingTopInset,
                bottom: windowTabInsertStickyTrackingBottomInset
            )
        case .stackSplit, .swap:
            targetWindow.moveNode.windowDragVisibleRect?.expanded(by: 16)
        case .detach, .workspaceMove, .sidebarWorkspaceMove:
            nil
    }
}

