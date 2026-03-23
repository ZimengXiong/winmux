import AppKit

@MainActor
private var pendingWindowDragIntent: PendingWindowDragIntent? = nil

private struct PendingWindowDragIntent {
    let sourceWindowId: UInt32
    let sourceSubject: WindowDragSubject
    let kind: WindowDragIntentKind
    let previewRect: Rect
    let interactionRect: Rect
    let title: String
    let subtitle: String
    let previewStyle: WindowTabDropPreviewStyle
    let isGroup: Bool
}

private enum WindowDragIntentKind: Equatable {
    case tabStack(targetWindowId: UInt32)
    case detachTab(windowId: UInt32)
    case swap(targetWindowId: UInt32)
    case moveToWorkspace(workspaceName: String)
    case createWorkspace
    case sidebarHover
}

enum WindowDragSubject: Equatable {
    case window
    case group
}

enum TabDetachOrigin {
    case window
    case tabStrip
}

private struct WindowDragIntentDestination {
    let kind: WindowDragIntentKind
    let previewRect: Rect
    let interactionRect: Rect
    let title: String
    let subtitle: String
    let previewStyle: WindowTabDropPreviewStyle
    let isGroup: Bool

    var preview: WindowTabDropPreviewViewModel {
        WindowTabDropPreviewViewModel(
            frame: previewRect.toAppKitScreenRect,
            title: title,
            subtitle: subtitle,
            style: previewStyle,
            isGroup: isGroup,
        )
    }
}

@MainActor
private func workspaceSidebarCursorPreviewRect(at mouseLocation: CGPoint) -> Rect {
    workspaceSidebarCursorPreviewRect(at: mouseLocation, sidebarRect: WorkspaceSidebarPanel.shared.visibleScreenRectNormalized())
}

private func workspaceSidebarCursorPreviewRect(at mouseLocation: CGPoint, sidebarRect: Rect?) -> Rect {
    let width: CGFloat = 184
    let height: CGFloat = 42
    if let sidebarRect {
        let horizontalInset: CGFloat = 10
        let verticalInset: CGFloat = 8
        let availableWidth = min(width, max(sidebarRect.width - horizontalInset * 2, 0))
        let clampedX = max(
            sidebarRect.minX + horizontalInset,
            min(mouseLocation.x - (availableWidth / 2), sidebarRect.maxX - availableWidth - horizontalInset),
        )
        let clampedY = max(
            sidebarRect.minY + verticalInset,
            min(mouseLocation.y - (height / 2), sidebarRect.maxY - height - verticalInset),
        )
        return Rect(
            topLeftX: clampedX,
            topLeftY: clampedY,
            width: availableWidth,
            height: height,
        )
    }
    return Rect(
        topLeftX: mouseLocation.x + 16,
        topLeftY: mouseLocation.y - height - 12,
        width: width,
        height: height,
    )
}

@MainActor
private func dragSubjectNode(for sourceWindow: Window, subject: WindowDragSubject) -> TreeNode {
    switch subject {
        case .window: sourceWindow
        case .group: sourceWindow.moveNode
    }
}

@MainActor
private func sidebarDragSourceTitle(for sourceWindow: Window, subject: WindowDragSubject) -> String {
    let moveNode = dragSubjectNode(for: sourceWindow, subject: subject)
    if let group = moveNode as? TilingContainer {
        let windowCount = max(moveNode.allLeafWindowsRecursive.count, 1)
        let representativeWindow =
            group.tabActiveWindow ??
            group.mostRecentWindowRecursive ??
            group.anyLeafWindowRecursive ??
            sourceWindow
        return "\(sidebarDisplayLabel(for: representativeWindow)) • \(windowCount) windows"
    }
    return sidebarDisplayLabel(for: sourceWindow)
}

@MainActor
private func updateSidebarDragFeedback(sourceWindow: Window, subject: WindowDragSubject, destination: WindowDragIntentDestination?) {
    guard let destination, destination.previewStyle == .sidebarWorkspaceMove else {
        let hadPinnedWindow = hasPinnedDraggedWindow()
        setPinnedDraggedWindowId(nil)
        setWorkspaceSidebarDropPreviewIfChanged(nil)
        if hadPinnedWindow {
            scheduleRefreshSession(.globalObserver("sidebarGhostExit"), optimisticallyPreLayoutWorkspaces: true)
        }
        return
    }

    let moveNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let isTabGroup = moveNode is TilingContainer
    let windowCount = max(moveNode.allLeafWindowsRecursive.count, 1)
    let sourceLabel = sidebarDragSourceTitle(for: sourceWindow, subject: subject)
    let targetWorkspaceName: String? = switch destination.kind {
        case .moveToWorkspace(let workspaceName): workspaceName
        case .createWorkspace: nil
        case .sidebarHover, .tabStack, .detachTab, .swap: nil
    }
    if case .moveToWorkspace = destination.kind {
        setWorkspaceSidebarDropPreviewIfChanged(WorkspaceSidebarDropPreviewViewModel(
            sourceWindowId: sourceWindow.windowId,
            label: sourceLabel,
            targetWorkspaceName: targetWorkspaceName,
            targetsNewWorkspace: false,
            isTabGroup: isTabGroup,
            windowCount: windowCount,
        ))
    } else if destination.kind == .createWorkspace {
        setWorkspaceSidebarDropPreviewIfChanged(WorkspaceSidebarDropPreviewViewModel(
            sourceWindowId: sourceWindow.windowId,
            label: sourceLabel,
            targetWorkspaceName: nil,
            targetsNewWorkspace: true,
            isTabGroup: isTabGroup,
            windowCount: windowCount,
        ))
    } else {
        setWorkspaceSidebarDropPreviewIfChanged(nil)
    }

    let pinnedWindowId = currentlyManipulatedWithMouseWindowId == sourceWindow.windowId ? sourceWindow.windowId : nil
    let previousPinnedWindowId = isPinnedDraggedWindow(sourceWindow.windowId) ? sourceWindow.windowId : nil
    if let pinnedWindowId, let anchorRect = draggedWindowAnchorRect(for: pinnedWindowId) {
        sourceWindow.setAxFrame(anchorRect.topLeftCorner, anchorRect.size)
    }
    if pinnedWindowId != previousPinnedWindowId {
        setPinnedDraggedWindowId(pinnedWindowId)
        scheduleRefreshSession(.globalObserver("sidebarGhostEnter"), optimisticallyPreLayoutWorkspaces: true)
    } else {
        setPinnedDraggedWindowId(pinnedWindowId)
    }
}

@MainActor
private func setWorkspaceSidebarDropPreviewIfChanged(_ preview: WorkspaceSidebarDropPreviewViewModel?) {
    if TrayMenuModel.shared.workspaceSidebarDropPreview != preview {
        TrayMenuModel.shared.workspaceSidebarDropPreview = preview
    }
}

@MainActor
private func currentWindowTabDropDestination(sourceWindow: Window, mouseLocation: CGPoint) -> WindowDragIntentDestination? {
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    return mouseLocation.findWindowTabDropDestination(in: targetWorkspace.rootTilingContainer, excluding: sourceWindow)
}

@MainActor
private func currentSidebarWorkspaceDropDestination(sourceWindow: Window, mouseLocation: CGPoint, subject: WindowDragSubject) -> WindowDragIntentDestination? {
    let sourceLabel = sidebarDragSourceTitle(for: sourceWindow, subject: subject)
    let isGroup = subject == .group
    if let target = workspaceSidebarDropTarget(at: mouseLocation) {
        switch target.kind {
            case .workspace(let workspaceName):
                if dragSubjectNode(for: sourceWindow, subject: subject).nodeWorkspace?.name != workspaceName {
                    return WindowDragIntentDestination(
                        kind: .moveToWorkspace(workspaceName: workspaceName),
                        previewRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                        interactionRect: target.rect.expanded(left: 14, right: 14, top: 12, bottom: 12),
                        title: sourceLabel,
                        subtitle: "Drop to send this item to \(workspaceName)",
                        previewStyle: .sidebarWorkspaceMove,
                        isGroup: isGroup,
                    )
                }
            case .newWorkspace:
                return WindowDragIntentDestination(
                    kind: .createWorkspace,
                    previewRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                    interactionRect: target.rect.expanded(left: 14, right: 14, top: 12, bottom: 12),
                    title: sourceLabel,
                    subtitle: "Drop to create a workspace and move this item there",
                    previewStyle: .sidebarWorkspaceMove,
                    isGroup: isGroup,
                )
        }
    }
    guard let sidebarRect = WorkspaceSidebarPanel.shared.visibleScreenRectNormalized(),
          sidebarRect.contains(mouseLocation)
    else { return nil }
    return WindowDragIntentDestination(
        kind: .sidebarHover,
        previewRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
        interactionRect: sidebarRect,
        title: sourceLabel,
        subtitle: "Drag across a workspace to move this item",
        previewStyle: .sidebarWorkspaceMove,
        isGroup: isGroup,
    )
}

@MainActor
private func currentTabDetachDestination(sourceWindow: Window, mouseLocation: CGPoint, origin: TabDetachOrigin) -> WindowDragIntentDestination? {
    guard let parent = sourceWindow.parent as? TilingContainer,
          parent.layout == .accordion,
          parent.children.count > 1,
          let keepRect = sourceWindow.tabDetachKeepRect(origin: origin),
          !keepRect.contains(mouseLocation),
          let previewRect = sourceWindow.tabDetachPreviewRect
    else { return nil }

    return WindowDragIntentDestination(
        kind: .detachTab(windowId: sourceWindow.windowId),
        previewRect: previewRect,
        interactionRect: previewRect.expanded(left: 18, right: 18, top: 10, bottom: 18),
        title: "Detach Tab",
        subtitle: "Release to pull this window out of the stack",
        previewStyle: .detach,
        isGroup: false,
    )
}

extension Window {
    @MainActor
    var tabDropZoneRect: Rect? {
        guard let rect = lastAppliedLayoutPhysicalRect else { return nil }
        return rect.tabInsertPreviewRect(barHeight: CGFloat(config.windowTabs.height))
    }

    @MainActor
    var tabDropInteractionRect: Rect? {
        guard let rect = lastAppliedLayoutPhysicalRect else { return nil }
        return rect.tabInsertInteractionRect(barHeight: CGFloat(config.windowTabs.height))
    }

    @MainActor
    var tabDetachPreviewRect: Rect? {
        if let parent = parent as? TilingContainer,
           parent.layout == .accordion,
           let rect = parent.lastAppliedLayoutPhysicalRect
        {
            return rect.insetBy(left: 10, right: 10, top: 10, bottom: 10)
        }
        return lastAppliedLayoutPhysicalRect?.insetBy(left: 10, right: 10, top: 10, bottom: 10)
    }

    @MainActor
    func tabDetachKeepRect(origin: TabDetachOrigin) -> Rect? {
        guard let parent = parent as? TilingContainer, parent.layout == .accordion else { return nil }
        return switch origin {
            case .window:
                parent.lastAppliedLayoutPhysicalRect?.insetBy(left: 24, right: 24, top: 14, bottom: 18)
            case .tabStrip:
                (parent.windowTabDropZoneRect ?? parent.windowTabBarRect)?.expanded(left: 4, right: 4, top: 4, bottom: 6)
        }
    }
}

extension CGPoint {
    @MainActor
    fileprivate func findWindowTabDropDestination(in tree: TilingContainer, excluding sourceWindow: Window) -> WindowDragIntentDestination? {
        findWindowTabDropDestination(in: tree as TreeNode, excluding: sourceWindow)
    }

    @MainActor
    private func findWindowTabDropDestination(in node: TreeNode, excluding sourceWindow: Window) -> WindowDragIntentDestination? {
        guard node.lastAppliedLayoutPhysicalRect?.contains(self) == true else { return nil }
        switch node.tilingTreeNodeCasesOrDie() {
            case .window(let window):
                guard window != sourceWindow,
                      let dropRect = window.tabDropZoneRect,
                      let interactionRect = window.tabDropInteractionRect,
                      interactionRect.contains(self)
                else { return nil }
                return WindowDragIntentDestination(
                    kind: .tabStack(targetWindowId: window.windowId),
                    previewRect: dropRect,
                    interactionRect: interactionRect,
                    title: "Insert Into Tabs",
                    subtitle: "Drop near the top edge to add this window",
                    previewStyle: .tabInsert,
                    isGroup: false,
                )
            case .tilingContainer(let container):
                if let targetWindow = container.tabActiveWindow,
                   targetWindow != sourceWindow,
                   let tabBarRect = targetWindow.tabDropZoneRect,
                   let interactionRect = targetWindow.tabDropInteractionRect,
                   interactionRect.contains(self)
                {
                    return WindowDragIntentDestination(
                        kind: .tabStack(targetWindowId: targetWindow.windowId),
                        previewRect: tabBarRect,
                        interactionRect: interactionRect,
                        title: "Insert Into Tabs",
                        subtitle: "Drop near the top edge to add this window",
                        previewStyle: .tabInsert,
                        isGroup: false,
                    )
                }

                switch container.layout {
                    case .tiles:
                        guard let child = container.children.first(where: { $0.lastAppliedLayoutPhysicalRect?.contains(self) == true }) else {
                            return nil
                        }
                        return findWindowTabDropDestination(in: child, excluding: sourceWindow)
                    case .accordion:
                        guard let child = container.mostRecentChild else { return nil }
                        return findWindowTabDropDestination(in: child, excluding: sourceWindow)
                }
        }
    }
}

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
    guard let destination = currentWindowDragIntentDestination(
        sourceWindow: sourceWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin
    ) else {
        updateSidebarDragFeedback(sourceWindow: sourceWindow, subject: subject, destination: nil)
        clearPendingWindowDragIntent()
        return false
    }
    updateSidebarDragFeedback(sourceWindow: sourceWindow, subject: subject, destination: destination)
    return setPendingWindowDragIntent(sourceWindowId: sourceWindow.windowId, sourceSubject: subject, destination: destination)
}

@MainActor
func updatePendingDetachedTabIntent(sourceWindow: Window, mouseLocation: CGPoint, origin: TabDetachOrigin) -> Bool {
    updatePendingWindowDragIntent(sourceWindow: sourceWindow, mouseLocation: mouseLocation, subject: .window, detachOrigin: origin)
}

@MainActor
func refreshPendingWindowDragIntentFromGlobalMouseDrag() {
    guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .move else {
        clearPendingWindowDragIntent()
        return
    }
    guard let windowId = currentlyManipulatedWithMouseWindowId,
          let sourceWindow = Window.get(byId: windowId)
    else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    _ = updatePendingWindowDragIntent(
        sourceWindow: sourceWindow,
        mouseLocation: mouseLocation,
        subject: getCurrentMouseDragSubject(),
        detachOrigin: getCurrentMouseTabDetachOrigin(),
    )
}

@MainActor
private func setPendingWindowDragIntent(sourceWindowId: UInt32, sourceSubject: WindowDragSubject, destination: WindowDragIntentDestination) -> Bool {
    if let pendingWindowDragIntent,
       pendingWindowDragIntent.sourceWindowId == sourceWindowId,
       pendingWindowDragIntent.sourceSubject == sourceSubject,
       pendingWindowDragIntent.kind == destination.kind,
       pendingWindowDragIntent.title == destination.title,
       pendingWindowDragIntent.subtitle == destination.subtitle,
       pendingWindowDragIntent.previewStyle == destination.previewStyle,
       pendingWindowDragIntent.isGroup == destination.isGroup,
       pendingWindowDragIntent.previewRect.isEqual(to: destination.previewRect),
       pendingWindowDragIntent.interactionRect.isEqual(to: destination.interactionRect)
    {
        return true
    }

    pendingWindowDragIntent = PendingWindowDragIntent(
        sourceWindowId: sourceWindowId,
        sourceSubject: sourceSubject,
        kind: destination.kind,
        previewRect: destination.previewRect,
        interactionRect: destination.interactionRect,
        title: destination.title,
        subtitle: destination.subtitle,
        previewStyle: destination.previewStyle,
        isGroup: destination.isGroup,
    )
    WindowTabDropPreviewPanel.shared.show(destination.preview)
    return true
}

@MainActor
func clearPendingWindowDragIntent() {
    pendingWindowDragIntent = nil
    setPinnedDraggedWindowId(nil)
    setWorkspaceSidebarDropPreviewIfChanged(nil)
    WindowTabDropPreviewPanel.shared.hide()
}

@MainActor
func applyPendingWindowDragIntentIfPossible() -> Bool {
    defer { clearPendingWindowDragIntent() }
    guard let pendingWindowDragIntent,
          let sourceWindow = Window.get(byId: pendingWindowDragIntent.sourceWindowId),
          pendingWindowDragIntent.interactionRect.contains(mouseLocation)
    else { return false }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: pendingWindowDragIntent.sourceSubject)
    switch pendingWindowDragIntent.kind {
        case .tabStack(let targetWindowId):
            guard pendingWindowDragIntent.sourceSubject == .window else { return false }
            guard let targetWindow = Window.get(byId: targetWindowId),
                  sourceWindow != targetWindow
            else { return false }
            resetClosedWindowsCache()
            createOrAppendWindowTabStack(sourceWindow: sourceWindow, onto: targetWindow)
            return true
        case .detachTab(let windowId):
            guard sourceWindow.windowId == windowId else { return false }
            resetClosedWindowsCache()
            return removeWindowFromTabStack(sourceWindow)
        case .swap(let targetWindowId):
            guard let targetWindow = Window.get(byId: targetWindowId)
            else { return false }
            resetClosedWindowsCache()
            swapNodes(sourceNode, targetWindow.moveNode)
            return true
        case .moveToWorkspace(let workspaceName):
            let targetWorkspace = Workspace.get(byName: workspaceName)
            resetClosedWindowsCache()
            if pendingWindowDragIntent.previewStyle == .sidebarWorkspaceMove {
                applySidebarWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, targetWorkspace: targetWorkspace)
            } else {
                applyWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, mouseLocation: mouseLocation, targetWorkspace: targetWorkspace)
            }
            return true
        case .createWorkspace:
            resetClosedWindowsCache()
            return createWorkspaceFromSidebarDrag(sourceNode: sourceNode, sourceWindow: sourceWindow)
        case .sidebarHover:
            return false
    }
}

@MainActor
func createOrAppendWindowTabStack(sourceWindow: Window, onto targetWindow: Window) {
    guard sourceWindow != targetWindow else { return }
    if let targetParent = targetWindow.parent as? TilingContainer,
       targetParent.layout == .accordion
    {
        let targetIndex = targetWindow.ownIndex.orDie()
        let sourceIndex = sourceWindow.ownIndex
        let sourceWasInTargetParent = sourceWindow.parent === targetParent
        sourceWindow.unbindFromParent()
        let insertIndex = if sourceWasInTargetParent, let sourceIndex {
            sourceIndex < targetIndex ? targetIndex : targetIndex + 1
        } else {
            targetIndex + 1
        }
        sourceWindow.bind(to: targetParent, adaptiveWeight: WEIGHT_AUTO, index: insertIndex)
        sourceWindow.markAsMostRecentChild()
        _ = sourceWindow.focusWindow()
        return
    }

    let targetBinding = targetWindow.unbindFromParent()
    let newOrientation = (targetBinding.parent as? TilingContainer)?.orientation.opposite ?? .h
    let newParent = TilingContainer(
        parent: targetBinding.parent,
        adaptiveWeight: targetBinding.adaptiveWeight,
        newOrientation,
        .accordion,
        index: targetBinding.index,
    )
    sourceWindow.unbindFromParent()
    targetWindow.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
    sourceWindow.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    sourceWindow.markAsMostRecentChild()
    _ = sourceWindow.focusWindow()
}

@MainActor
@discardableResult
func removeWindowFromTabStack(_ window: Window) -> Bool {
    guard let parent = window.parent as? TilingContainer, parent.layout == .accordion else {
        return false
    }

    if let grandParent = parent.parent as? TilingContainer {
        let parentIndex = parent.ownIndex.orDie()
        window.unbindFromParent()
        window.bind(to: grandParent, adaptiveWeight: WEIGHT_AUTO, index: parentIndex + 1)
        window.markAsMostRecentChild()
        _ = window.focusWindow()
        return true
    }

    guard parent.parent is Workspace else { return false }
    let remainingChildren = parent.children.filter { $0 != window }
    let accordionOrientation = parent.orientation

    window.unbindFromParent()
    parent.layout = .tiles
    parent.changeOrientation(accordionOrientation.opposite)

    if remainingChildren.count > 1 {
        let nestedAccordion = TilingContainer(
            parent: parent,
            adaptiveWeight: WEIGHT_AUTO,
            accordionOrientation,
            .accordion,
            index: 0,
        )
        for child in remainingChildren {
            child.unbindFromParent()
            child.bind(to: nestedAccordion, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
    }

    window.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    window.markAsMostRecentChild()
    _ = window.focusWindow()
    return true
}

@MainActor
private func currentWindowDragIntentDestination(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if let sidebarDestination = currentSidebarWorkspaceDropDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation, subject: subject) {
        return sidebarDestination
    }

    if let sticky = pendingWindowDragIntent,
       sticky.sourceWindowId == sourceWindow.windowId,
       sticky.sourceSubject == subject,
       sticky.previewStyle != .sidebarWorkspaceMove,
       sticky.interactionRect.contains(mouseLocation)
    {
        return WindowDragIntentDestination(
            kind: sticky.kind,
            previewRect: sticky.previewRect,
            interactionRect: sticky.interactionRect,
            title: sticky.title,
            subtitle: sticky.subtitle,
            previewStyle: sticky.previewStyle,
            isGroup: sticky.isGroup,
        )
    }

    if subject == .window,
       config.windowTabs.enabled,
       let tabDestination = currentWindowTabDropDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation)
    {
        return tabDestination
    }

    if subject == .window,
       let detachDestination = currentTabDetachDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation, origin: detachOrigin) {
        return detachDestination
    }

    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    if targetWorkspace != sourceNode.nodeWorkspace {
        let previewRect = targetWorkspace.rootTilingContainer.lastAppliedLayoutPhysicalRect ?? targetWorkspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        return WindowDragIntentDestination(
            kind: .moveToWorkspace(workspaceName: targetWorkspace.name),
            previewRect: previewRect,
            interactionRect: previewRect,
            title: "Move Here",
            subtitle: "Drop to move this item to this workspace",
            previewStyle: .workspaceMove,
            isGroup: subject == .group,
        )
    }

    return currentSwapDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation, subject: subject)
}

@MainActor
private func currentSwapDestination(sourceWindow: Window, mouseLocation: CGPoint, subject: WindowDragSubject) -> WindowDragIntentDestination? {
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    guard let targetWindow = mouseLocation.findIn(tree: targetWorkspace.rootTilingContainer, virtual: false) else { return nil }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetNode = targetWindow.moveNode
    guard let previewRect = targetNode.swapDropZoneRect else { return nil }
    let interactionRect = if subject == .group {
        previewRect.expanded(left: 4, right: 4, top: 4, bottom: 6)
    } else {
        previewRect.expanded(left: 10, right: 10, top: 6, bottom: 10)
    }
    guard sourceNode != targetNode,
          interactionRect.contains(mouseLocation)
    else { return nil }
    let isTabGroup = targetNode is TilingContainer
    return WindowDragIntentDestination(
        kind: .swap(targetWindowId: targetWindow.windowId),
        previewRect: previewRect,
        interactionRect: interactionRect,
        title: isTabGroup ? "Swap With Tab Group" : "Swap Positions",
        subtitle: isTabGroup ? "Drop in the body to move around the whole group" : "Drop in the body to swap these windows",
        previewStyle: .swap,
        isGroup: subject == .group,
    )
}

@MainActor
private func applySidebarWorkspaceMove(sourceNode: TreeNode, sourceWindow: Window, targetWorkspace: Workspace) {
    let targetContainer: NonLeafTreeNodeObject
    if sourceNode is Window, sourceWindow.isFloating {
        targetContainer = targetWorkspace
    } else {
        targetContainer = targetWorkspace.rootTilingContainer
    }
    sourceNode.bind(to: targetContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    _ = sourceWindow.focusWindow()
}

@MainActor
private func applyWorkspaceMove(sourceNode: TreeNode, sourceWindow: Window, mouseLocation: CGPoint, targetWorkspace: Workspace) {
    let swapTarget = mouseLocation.findIn(tree: targetWorkspace.rootTilingContainer, virtual: false)?.takeIf { $0.moveNode != sourceNode }
    let index: Int
    if let swapTarget {
        let targetNode = swapTarget.moveNode
        if let targetParent = targetNode.parent as? TilingContainer, let targetRect = targetNode.lastAppliedLayoutPhysicalRect {
            index = mouseLocation.getProjection(targetParent.orientation) >= targetRect.center.getProjection(targetParent.orientation)
                ? targetNode.ownIndex.orDie() + 1
                : targetNode.ownIndex.orDie()
        } else {
            index = 0
        }
    } else {
        index = 0
    }
    sourceNode.bind(
        to: swapTarget?.moveNode.parent ?? targetWorkspace.rootTilingContainer,
        adaptiveWeight: WEIGHT_AUTO,
        index: index,
    )
    _ = sourceWindow.focusWindow()
}

private extension Rect {
    func insetBy(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> Rect {
        Rect(
            topLeftX: topLeftX + left,
            topLeftY: topLeftY + top,
            width: width - left - right,
            height: height - top - bottom,
        )
    }

    func expanded(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> Rect {
        insetBy(left: -left, right: -right, top: -top, bottom: -bottom)
    }

    func expanded(by amount: CGFloat) -> Rect {
        Rect(topLeftX: topLeftX - amount, topLeftY: topLeftY - amount, width: width + 2 * amount, height: height + 2 * amount)
    }

    func isEqual(to other: Rect) -> Bool {
        topLeftX == other.topLeftX && topLeftY == other.topLeftY && width == other.width && height == other.height
    }
}

extension TilingContainer {
    @MainActor
    var windowTabDropZoneRect: Rect? {
        guard showsWindowTabs, let rect = lastAppliedLayoutPhysicalRect else { return nil }
        return rect.tabInsertPreviewRect(barHeight: windowTabBarHeight)
    }

    @MainActor
    var windowTabDropInteractionRect: Rect? {
        guard showsWindowTabs, let rect = lastAppliedLayoutPhysicalRect else { return nil }
        return rect.tabInsertInteractionRect(barHeight: windowTabBarHeight)
    }
}

extension TreeNode {
    @MainActor
    var swapDropZoneRect: Rect? {
        guard let rect = lastAppliedLayoutPhysicalRect else { return nil }
        let insetX = min(max(rect.width * 0.08, 12), 28)
        let insetY = min(max(rect.height * 0.08, 12), 24)
        let topExclusion: CGFloat = switch self {
            case let window as Window:
                (window.tabDropInteractionRect?.height ?? 0) + 8
            case let container as TilingContainer:
                (container.windowTabDropInteractionRect?.height ?? 0) + 8
            default:
                0
        }
        let swapRect = rect.insetBy(
            left: min(insetX, rect.width * 0.2),
            right: min(insetX, rect.width * 0.2),
            top: min(max(topExclusion, insetY), rect.height * 0.45),
            bottom: min(insetY, rect.height * 0.18),
        )
        if swapRect.width >= 48, swapRect.height >= 28 {
            return swapRect
        }
        let fallbackTopInset = min(topExclusion, rect.height * 0.35)
        let fallbackRect = rect.insetBy(left: 0, right: 0, top: fallbackTopInset, bottom: 0)
        return fallbackRect.width > 0 && fallbackRect.height > 0 ? fallbackRect : nil
    }
}

private extension Rect {
    func tabInsertPreviewRect(barHeight: CGFloat) -> Rect {
        let topInset = min(max(barHeight * 0.08, 3), 6)
        let effectiveHeight = min(max(barHeight + 14, 40), max(height - topInset, 0))
        let sideInset = min(max(width * 0.04, 8), 18)
        return insetBy(
            left: sideInset,
            right: sideInset,
            top: topInset,
            bottom: max(height - effectiveHeight - topInset, 0),
        )
    }

    func tabInsertInteractionRect(barHeight: CGFloat) -> Rect {
        tabInsertPreviewRect(barHeight: barHeight).expanded(left: 24, right: 24, top: 12, bottom: 14)
    }
}
