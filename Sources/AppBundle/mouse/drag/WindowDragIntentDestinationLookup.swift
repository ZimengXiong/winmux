import AppKit

@MainActor
func currentWindowDragIntentDestination(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if let sidebarDestination = currentSidebarWorkspaceDropDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation, subject: subject) {
        return sidebarDestination
    }
    if isMouseInsideWorkspaceSidebar(mouseLocation) {
        return nil
    }

    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    let sourceWorkspace = sourceNode.nodeWorkspace
    if let surfaceDestination = currentWindowSurfaceDestinationIfAllowed(
        sourceWindow: sourceWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
        targetWorkspace: targetWorkspace,
        sourceWorkspace: sourceWorkspace,
    ) {
        return surfaceDestination
    }

    if let stickyDestination = currentStickyWindowDragIntentDestination(
        sourceWindow: sourceWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    ) {
        return stickyDestination
    }

    if subject == .window,
       detachOrigin != .tabStrip,
       let detachDestination = currentTabDetachDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation, origin: detachOrigin)
    {
        return detachDestination
    }

    return workspaceZoneMoveDestination(
        targetWorkspace: targetWorkspace,
        sourceWorkspace: sourceWorkspace,
        mouseLocation: mouseLocation,
        subject: subject,
    ) ?? workspaceMoveDestination(
        targetWorkspace: targetWorkspace,
        sourceWorkspace: sourceWorkspace,
        subject: subject,
    )
}

@MainActor
private func isMouseInsideWorkspaceSidebar(_ mouseLocation: CGPoint) -> Bool {
    WorkspaceSidebarPanel.panel(containing: mouseLocation) != nil
}

@MainActor
private func currentWindowSurfaceDestinationIfAllowed(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    targetWorkspace: Workspace,
    sourceWorkspace: Workspace?,
) -> WindowDragIntentDestination? {
    let canOfferWindowSurfaceIntent = if targetWorkspace == sourceWorkspace {
        shouldAllowSameWorkspaceWindowSurfaceIntent(
            subject: subject,
            detachOrigin: detachOrigin,
            isOptionPressed: currentSessionModifierFlags().contains(.maskAlternate),
        )
    } else {
        true
    }
    guard canOfferWindowSurfaceIntent else { return nil }
    return currentWindowSurfaceDestination(
        sourceWindow: sourceWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    )
}

@MainActor
private func workspaceZoneMoveDestination(
    targetWorkspace: Workspace,
    sourceWorkspace: Workspace?,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
) -> WindowDragIntentDestination? {
    guard targetWorkspace != sourceWorkspace else { return nil }
    let workspaceRect = targetWorkspace.workspaceMonitor.visibleRectPaddedByOuterGaps
    guard let zone = WindowIntentZoneBuilder.zone(at: mouseLocation, in: workspaceRect),
          zone.stackSplitPosition != nil,
          let previewZone = WindowIntentZoneBuilder.zones(in: workspaceRect).first(where: { $0.zone == zone })
    else {
        return nil
    }
    return WindowDragIntentDestination(
        kind: .moveToWorkspaceZone(workspaceName: targetWorkspace.name, zone: zone),
        previewRect: previewZone.frame,
        interactionRect: workspaceRect,
        title: zone.workspaceMoveTitle,
        subtitle: "Drop to move this item to \(targetWorkspace.name)",
        previewStyle: zone.previewStyleForWorkspaceMove,
        previewGeometry: zone.previewGeometryForWorkspaceMove,
        isGroup: subject == .group,
        dropIntentOverlay: WindowDropIntentOverlayModel(
            targetFrame: workspaceRect,
            activeZone: zone,
            cornerRadius: nil,
        ),
    )
}

private extension WindowDropZone {
    var previewStyleForWorkspaceMove: WindowTabDropPreviewStyle {
        switch self {
            case .left, .right, .top, .bottom:
                .stackSplit
            case .tab, .middle:
                .workspaceMove
        }
    }

    var previewGeometryForWorkspaceMove: WindowTabDropPreviewGeometry {
        switch self {
            case .left:
                .splitLeft
            case .right:
                .splitRight
            case .top:
                .splitAbove
            case .bottom:
                .splitBelow
            case .tab, .middle:
                .rounded
        }
    }

    var workspaceMoveTitle: String {
        switch self {
            case .left:
                "Move Left"
            case .right:
                "Move Right"
            case .top:
                "Move Above"
            case .bottom:
                "Move Below"
            case .tab, .middle:
                "Move Here"
        }
    }
}

@MainActor
private func workspaceMoveDestination(
    targetWorkspace: Workspace,
    sourceWorkspace: Workspace?,
    subject: WindowDragSubject,
) -> WindowDragIntentDestination? {
    guard targetWorkspace != sourceWorkspace else { return nil }
    let previewRect = targetWorkspace.workspaceMonitor.visibleRectPaddedByOuterGaps
    return WindowDragIntentDestination(
        kind: .moveToWorkspace(workspaceName: targetWorkspace.name),
        previewRect: previewRect,
        interactionRect: previewRect,
        title: "Move Here",
        subtitle: "Drop to move this item to this workspace",
        previewStyle: .workspaceMove,
        previewGeometry: .rounded,
        isGroup: subject == .group,
    )
}
