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

    return workspaceMoveDestination(
        targetWorkspace: targetWorkspace,
        sourceWorkspace: sourceWorkspace,
        subject: subject,
    )
}

@MainActor
private func isMouseInsideWorkspaceSidebar(_ mouseLocation: CGPoint) -> Bool {
    WorkspaceSidebarPanel.shared.visibleScreenRectNormalized()?.contains(mouseLocation) == true
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
    let isOptionPressed = currentSessionModifierFlags().contains(.maskAlternate)
    let canOfferWindowSurfaceIntent = if targetWorkspace == sourceWorkspace {
        shouldAllowSameWorkspaceWindowSurfaceIntent(
            enableWindowManagement: config.enableWindowManagement,
            subject: subject,
            detachOrigin: detachOrigin,
            isOptionPressed: isOptionPressed,
        )
    } else {
        config.enableWindowManagement
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
private func workspaceMoveDestination(
    targetWorkspace: Workspace,
    sourceWorkspace: Workspace?,
    subject: WindowDragSubject,
) -> WindowDragIntentDestination? {
    guard targetWorkspace != sourceWorkspace else { return nil }
    let previewRect = targetWorkspace.workspaceMonitor.visibleRectPaddedByOuterGaps
    return WindowDragIntentDestination(
        kind: .moveToWorkspace(workspaceName: targetWorkspace.name),
        previewContainerRect: previewRect,
        previewRect: previewRect,
        interactionRect: previewRect,
        title: "Move Here",
        subtitle: "Drop to move this item to this workspace",
        previewStyle: .workspaceMove,
        previewGeometry: .rounded,
        isGroup: subject == .group,
    )
}
