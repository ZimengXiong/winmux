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

enum WindowDragIntentKind: Equatable {
    case tabStack(targetWindowId: UInt32)
    case detachTab(windowId: UInt32)
    case swap(targetWindowId: UInt32)
    case moveToWorkspace(workspaceName: String)
    case createWorkspace
    case sidebarHover
}

@MainActor
func isWindowDragIntentKindEnabled(_ kind: WindowDragIntentKind) -> Bool {
    switch kind {
        case .tabStack:
            return config.windowTabs.enabled
        case .detachTab, .swap, .moveToWorkspace, .createWorkspace, .sidebarHover:
            return true
    }
}

func shouldUseStickyWindowDragIntent(previewStyle: WindowTabDropPreviewStyle) -> Bool {
    switch previewStyle {
        case .tabInsert, .swap:
            return true
        case .detach, .workspaceMove, .sidebarWorkspaceMove:
            return false
    }
}

enum WindowDragSubject: Equatable {
    case window
    case group
}

enum TabDetachOrigin: Equatable {
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
        let pinnedWindowRect = pinnedDraggedWindowRect(
            for: sourceWindow,
            subject: subject,
            fallbackAnchorRect: anchorRect,
        )
        sourceWindow.setAxFrame(pinnedWindowRect.topLeftCorner, pinnedWindowRect.size)
    }
    if pinnedWindowId != previousPinnedWindowId {
        setPinnedDraggedWindowId(pinnedWindowId)
        scheduleRefreshSession(.globalObserver("sidebarGhostEnter"), optimisticallyPreLayoutWorkspaces: true)
    } else {
        setPinnedDraggedWindowId(pinnedWindowId)
    }
}

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
private func setWorkspaceSidebarDropPreviewIfChanged(_ preview: WorkspaceSidebarDropPreviewViewModel?) {
    if TrayMenuModel.shared.workspaceSidebarDropPreview != preview {
        TrayMenuModel.shared.workspaceSidebarDropPreview = preview
    }
}

@MainActor
private func tabStackDestination(targetWindow: Window, mouseLocation: CGPoint? = nil) -> WindowDragIntentDestination? {
    guard isWindowDragIntentKindEnabled(.tabStack(targetWindowId: targetWindow.windowId)),
          let dropRect = targetWindow.tabDropZoneRect,
          let interactionRect = targetWindow.tabDropInteractionRect,
          mouseLocation.map(interactionRect.contains) ?? true
    else { return nil }
    return WindowDragIntentDestination(
        kind: .tabStack(targetWindowId: targetWindow.windowId),
        previewRect: dropRect,
        interactionRect: interactionRect,
        title: "Insert Into Tabs",
        subtitle: "Drop near the top edge to add this window",
        previewStyle: .tabInsert,
        isGroup: false,
    )
}

@MainActor
private func swapDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint? = nil,
    subject: WindowDragSubject,
) -> WindowDragIntentDestination? {
    if shouldSuppressSwapDestination(sourceWindow: sourceWindow, subject: subject) {
        return nil
    }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetNode = targetWindow.moveNode
    guard sourceNode != targetNode,
          !sourceNode.parentsWithSelf.contains(targetNode),
          !targetNode.parentsWithSelf.contains(sourceNode),
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
        previewRect: previewRect,
        interactionRect: interactionRect,
        title: isTabGroup ? "Swap With Tab Group" : "Swap Positions",
        subtitle: isTabGroup ? "Drop in the body to move around the whole group" : "Drop in the body to swap these windows",
        previewStyle: .swap,
        isGroup: subject == .group,
    )
}

@MainActor
private func currentWindowTabDropDestination(sourceWindow: Window, mouseLocation: CGPoint) -> WindowDragIntentDestination? {
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    return mouseLocation.findWindowTabDropDestination(in: targetWorkspace.rootTilingContainer, excluding: sourceWindow)
}

func isActionableSidebarWorkspaceDropTarget(
    sourceWorkspaceName: String?,
    targetKind: WorkspaceSidebarDropTargetKind?,
) -> Bool {
    switch targetKind {
        case .workspace(let workspaceName):
            return sourceWorkspaceName != workspaceName
        case .newWorkspace:
            return true
        case nil:
            return false
    }
}

@MainActor
private func currentSidebarWorkspaceDropDestination(sourceWindow: Window, mouseLocation: CGPoint, subject: WindowDragSubject) -> WindowDragIntentDestination? {
    let sourceLabel = sidebarDragSourceTitle(for: sourceWindow, subject: subject)
    let isGroup = subject == .group
    let sourceWorkspaceName = dragSubjectNode(for: sourceWindow, subject: subject).nodeWorkspace?.name
    if let target = workspaceSidebarDropTarget(at: mouseLocation),
       isActionableSidebarWorkspaceDropTarget(sourceWorkspaceName: sourceWorkspaceName, targetKind: target.kind)
    {
        switch target.kind {
            case .workspace(let workspaceName):
                return WindowDragIntentDestination(
                    kind: .moveToWorkspace(workspaceName: workspaceName),
                    previewRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                    interactionRect: target.rect.expanded(left: 14, right: 14, top: 12, bottom: 12),
                    title: sourceLabel,
                    subtitle: "Drop to send this item to \(workspaceName)",
                    previewStyle: .sidebarWorkspaceMove,
                    isGroup: isGroup,
                )
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
    return nil
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

@MainActor
func shouldSuppressSameAccordionTabDestination(sourceWindow: Window, targetWindow: Window, detachOrigin _: TabDetachOrigin) -> Bool {
    guard let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .accordion,
          targetWindow.parent === sourceParent
    else { return false }
    return true
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
            return rect.insetBy(left: 2, right: 2, top: 2, bottom: 2)
        }
        return lastAppliedLayoutPhysicalRect?.insetBy(left: 2, right: 2, top: 2, bottom: 2)
    }

    @MainActor
    func tabDetachKeepRect(origin: TabDetachOrigin) -> Rect? {
        guard let parent = parent as? TilingContainer, parent.layout == .accordion else { return nil }
        return switch origin {
            case .window:
                lastAppliedLayoutPhysicalRect?.expanded(left: 8, right: 8, top: 8, bottom: 12)
                    ?? parent.lastAppliedLayoutPhysicalRect?.insetBy(left: 24, right: 24, top: 14, bottom: 18)
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
                guard window != sourceWindow else { return nil }
                return tabStackDestination(targetWindow: window, mouseLocation: self)
            case .tilingContainer(let container):
                if let targetWindow = container.tabActiveWindow, targetWindow != sourceWindow,
                   let destination = tabStackDestination(targetWindow: targetWindow, mouseLocation: self)
                {
                    return destination
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
private func currentStickyWindowDragIntentDestination(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    guard let sticky = pendingWindowDragIntent,
          sticky.sourceWindowId == sourceWindow.windowId,
          sticky.sourceSubject == subject,
          shouldUseStickyWindowDragIntent(previewStyle: sticky.previewStyle),
          sticky.interactionRect.contains(mouseLocation)
    else { return nil }

    switch sticky.kind {
        case .tabStack(let targetWindowId):
            guard subject == .window,
                  let targetWindow = Window.get(byId: targetWindowId),
                  targetWindow != sourceWindow,
                  !shouldSuppressSameAccordionTabDestination(
                      sourceWindow: sourceWindow,
                      targetWindow: targetWindow,
                      detachOrigin: detachOrigin
                  )
            else { return nil }
            return tabStackDestination(targetWindow: targetWindow, mouseLocation: mouseLocation)
        case .swap(let targetWindowId):
            guard let targetWindow = Window.get(byId: targetWindowId) else { return nil }
            return swapDestination(
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                mouseLocation: mouseLocation,
                subject: subject,
            )
        case .detachTab, .moveToWorkspace, .createWorkspace, .sidebarHover:
            return nil
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
    // Show cursor drag proxy during sidebar-originated drags
    // or tab-strip-originated drags when hovering over the sidebar
    let showCursorProxy: Bool = {
        if getCurrentMouseDragStartedInSidebar() { return true }
        if detachOrigin == .tabStrip,
           let sidebarRect = WorkspaceSidebarPanel.shared.visibleScreenRectNormalized(),
           sidebarRect.contains(mouseLocation)
        { return true }
        return false
    }()
    if showCursorProxy {
        let label = sidebarDragSourceTitle(for: sourceWindow, subject: subject)
        let isGroup = subject == .group || dragSubjectNode(for: sourceWindow, subject: subject) is TilingContainer
        WindowDragCursorProxyPanel.shared.show(
            label: label,
            isGroup: isGroup,
            mouseScreenPoint: NSEvent.mouseLocation,
        )
    } else if detachOrigin == .tabStrip {
        WindowDragCursorProxyPanel.shared.hide()
    }

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
    WindowDragCursorProxyPanel.shared.hide()
}

@MainActor
func applyPendingWindowDragIntentIfPossible() -> Bool {
    defer { clearPendingWindowDragIntent() }
    guard let pendingWindowDragIntent,
          let sourceWindow = Window.get(byId: pendingWindowDragIntent.sourceWindowId),
          pendingWindowDragIntent.interactionRect.contains(mouseLocation),
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
            createOrAppendWindowTabStack(sourceWindow: sourceWindow, onto: targetWindow)
            return true
        case .detachTab(let windowId):
            guard sourceWindow.windowId == windowId else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            return removeWindowFromTabStack(sourceWindow)
        case .swap(let targetWindowId):
            guard let targetWindow = Window.get(byId: targetWindowId)
            else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            return applyWindowSwapDragIntent(
                sourceWindow: sourceWindow,
                sourceSubject: pendingWindowDragIntent.sourceSubject,
                targetWindow: targetWindow,
            )
        case .moveToWorkspace(let workspaceName):
            guard let targetWorkspace = Workspace.existing(byName: workspaceName) else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            if pendingWindowDragIntent.previewStyle == .sidebarWorkspaceMove {
                applySidebarWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, targetWorkspace: targetWorkspace)
            } else {
                applyWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, mouseLocation: mouseLocation, targetWorkspace: targetWorkspace)
            }
            return true
        case .createWorkspace:
            syncClosedWindowsCacheToCurrentWorld()
            return createWorkspaceFromSidebarDrag(sourceNode: sourceNode, sourceWindow: sourceWindow)
        case .sidebarHover:
            return false
    }
}

@MainActor
func applyWindowSwapDragIntent(
    sourceWindow: Window,
    sourceSubject: WindowDragSubject,
    targetWindow: Window,
) -> Bool {
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: sourceSubject)
    swapNodes(sourceNode, targetWindow.moveNode)
    return sourceWindow.focusWindow()
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
        window.unbindFromParent()
        if parent.children.count == 1 {
            let parentBinding = parent.unbindFromParent()
            let remainingChild = parent.children.singleOrNil().orDie()
            remainingChild.unbindFromParent()
            remainingChild.bind(to: grandParent, adaptiveWeight: parentBinding.adaptiveWeight, index: parentBinding.index)
            window.bind(to: grandParent, adaptiveWeight: WEIGHT_AUTO, index: parentBinding.index + 1)
        } else {
            let parentIndex = parent.ownIndex.orDie()
            window.bind(to: grandParent, adaptiveWeight: WEIGHT_AUTO, index: parentIndex + 1)
        }
        window.markAsMostRecentChild()
        _ = window.focusWindow()
        return true
    }

    guard parent.parent is Workspace else { return false }
    let remainingChildren = parent.children.filter { $0 != window }
    let accordionOrientation = parent.orientation

    window.unbindFromParent()
    let remainingMostRecentChild = parent.mostRecentChild
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
        remainingMostRecentChild?.markAsMostRecentChild()
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

    // Suppress window drop hints when the mouse is within the sidebar's
    // visible bounds during any drag — windows behind the sidebar
    // should never show hints since they're visually obscured.
    if let sidebarRect = WorkspaceSidebarPanel.shared.visibleScreenRectNormalized(),
       sidebarRect.contains(mouseLocation)
    {
        return nil
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
       config.windowTabs.enabled,
       let tabDestination = currentWindowTabDropDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation)
    {
        if case .tabStack(let targetWindowId) = tabDestination.kind,
           let targetWindow = Window.get(byId: targetWindowId),
           shouldSuppressSameAccordionTabDestination(
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

    if subject == .window,
       let detachDestination = currentTabDetachDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation, origin: detachOrigin) {
        return detachDestination
    }

    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    if targetWorkspace != sourceNode.nodeWorkspace {
        let previewRect = targetWorkspace.workspaceMonitor.visibleRectPaddedByOuterGaps
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
    return swapDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        mouseLocation: mouseLocation,
        subject: subject,
    )
}

func shouldSuppressSwapDestination(sourceWindow: Window, subject: WindowDragSubject) -> Bool {
    subject == .window && sourceWindow.isFloating
}

@MainActor
private func applySidebarWorkspaceMove(sourceNode: TreeNode, sourceWindow: Window, targetWorkspace: Workspace) {
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
private func workspaceSiblingInsertionRoot(_ workspace: Workspace) -> TilingContainer {
    let root = workspace.rootTilingContainer
    guard root.layout == .accordion, !root.children.isEmpty else { return root }

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
        // Exclude the top region where the tab insert interaction zone lives,
        // so dragging over the top ~20% triggers the tab group hint instead.
        let topExclusion: CGFloat = switch self {
            case let window as Window:
                (window.tabDropInteractionRect?.height ?? rect.height * 0.2) + 4
            case let container as TilingContainer:
                (container.windowTabDropInteractionRect?.height ?? rect.height * 0.2) + 4
            default:
                max(rect.height * 0.2, 40)
        }
        let swapRect = rect.insetBy(
            left: 2,
            right: 2,
            top: min(topExclusion, rect.height * 0.4),
            bottom: 2,
        )
        guard swapRect.width > 0, swapRect.height > 0 else { return nil }
        return swapRect
    }
}

private extension Rect {
    func tabInsertPreviewRect(barHeight: CGFloat) -> Rect {
        // Show the border at the full width of the window, cropped to
        // the tab bar region height so it outlines the top strip area.
        let effectiveHeight = min(max(barHeight + 8, 36), max(height, 0))
        return insetBy(
            left: 2,
            right: 2,
            top: 2,
            bottom: max(height - effectiveHeight, 0),
        )
    }

    func tabInsertInteractionRect(barHeight: CGFloat) -> Rect {
        tabInsertPreviewRect(barHeight: barHeight).expanded(left: 20, right: 20, top: 10, bottom: 12)
    }
}
