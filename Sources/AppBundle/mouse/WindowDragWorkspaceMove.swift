import AppKit
import Common

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

    // Suppress window drop hints when the mouse is within the sidebar's
    // visible bounds during any drag — windows behind the sidebar
    // should never show hints since they're visually obscured.
    if let sidebarRect = WorkspaceSidebarPanel.shared.visibleScreenRectNormalized(),
       sidebarRect.contains(mouseLocation)
    {
        return nil
    }

    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    let isOptionPressed = currentSessionModifierFlags().contains(.maskAlternate)
    let sourceWorkspace = sourceNode.nodeWorkspace
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

    if canOfferWindowSurfaceIntent,
       let surfaceDestination = currentWindowSurfaceDestination(
           sourceWindow: sourceWindow,
           mouseLocation: mouseLocation,
           subject: subject,
           detachOrigin: detachOrigin,
       )
    {
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

    if targetWorkspace != sourceWorkspace {
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

    return nil
}

func shouldSuppressSwapDestination(sourceWindow: Window, subject: WindowDragSubject) -> Bool {
    subject == .window && sourceWindow.isFloating
}

@MainActor
func applySidebarWorkspaceMove(sourceNode: TreeNode, sourceWindow: Window, targetWorkspace: Workspace) {
    if sourceNode is Window, sourceWindow.isFloating {
        sourceNode.bind(to: targetWorkspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    } else {
        let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
        sourceNode.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
    }
    _ = sourceWindow.focusWindow()
}

// Internal to keep cross-workspace insertion semantics unit-testable.
@MainActor
func applyWorkspaceMove(sourceNode: TreeNode, sourceWindow: Window, mouseLocation: CGPoint, targetWorkspace: Workspace) {
    if sourceNode is Window, sourceWindow.isFloating {
        sourceNode.bind(to: targetWorkspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        _ = sourceWindow.focusWindow()
        return
    }
    let swapTarget = mouseLocation.findIn(tree: targetWorkspace.rootTilingContainer, virtual: false)?.takeIf { $0.moveNode != sourceNode }
    let binding = workspaceMoveBindingData(
        targetWorkspace: targetWorkspace,
        swapTarget: swapTarget,
        mouseLocation: mouseLocation,
    )
    sourceNode.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
    _ = sourceWindow.focusWindow()
}

@MainActor
func workspaceMoveBindingData(
    targetWorkspace: Workspace,
    swapTarget: Window?,
    mouseLocation: CGPoint,
) -> BindingData {
    guard let swapTarget else {
        return workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
    }

    let targetNode = swapTarget.moveNode
    if let targetParent = targetNode.parent as? TilingContainer,
       let targetRect = targetNode.lastAppliedLayoutPhysicalRect
    {
        let index = mouseLocation.getProjection(targetParent.orientation) >= targetRect.center.getProjection(targetParent.orientation)
            ? targetNode.ownIndex.orDie() + 1
            : targetNode.ownIndex.orDie()
        return BindingData(
            parent: targetParent,
            adaptiveWeight: WEIGHT_AUTO,
            index: index,
        )
    }

    if targetNode === targetWorkspace.rootTilingContainer {
        let targetRect = targetNode.lastAppliedLayoutPhysicalRect ?? targetWorkspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        let insertionParent = workspaceSiblingInsertionRoot(targetWorkspace)
        let index = mouseLocation.getProjection(insertionParent.orientation) >= targetRect.center.getProjection(insertionParent.orientation)
            ? 1
            : 0
        return BindingData(
            parent: insertionParent,
            adaptiveWeight: WEIGHT_AUTO,
            index: index,
        )
    }

    return BindingData(
        parent: targetWorkspace.rootTilingContainer,
        adaptiveWeight: WEIGHT_AUTO,
        index: 0,
    )
}

@MainActor
func workspaceAppendBindingData(targetWorkspace: Workspace, index: Int) -> BindingData {
    BindingData(
        parent: workspaceSiblingInsertionRoot(targetWorkspace),
        adaptiveWeight: WEIGHT_AUTO,
        index: index,
    )
}

@MainActor
func workspaceSiblingInsertionRoot(_ workspace: Workspace) -> TilingContainer {
    let root = workspace.rootTilingContainer
    guard root.layout == .tabGroup, !root.children.isEmpty else { return root }

    let previousRoot = root
    previousRoot.unbindFromParent()
    _ = TilingContainer(
        parent: workspace,
        adaptiveWeight: WEIGHT_AUTO,
        previousRoot.orientation.opposite,
        .tiles,
        index: 0,
    )
    previousRoot.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: 0)
    return workspace.rootTilingContainer
}
