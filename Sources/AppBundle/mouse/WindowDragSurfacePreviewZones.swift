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
