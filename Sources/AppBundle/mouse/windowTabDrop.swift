import AppKit

@MainActor
private var pendingWindowDragIntent: PendingWindowDragIntent? = nil

private struct PendingWindowDragIntent {
    let sourceWindowId: UInt32
    let kind: WindowDragIntentKind
    let previewRect: Rect
    let interactionRect: Rect
    let title: String
    let subtitle: String
    let previewStyle: WindowTabDropPreviewStyle
}

private enum WindowDragIntentKind: Equatable {
    case tabStack(targetWindowId: UInt32)
    case detachTab(windowId: UInt32)
    case swap(targetWindowId: UInt32)
    case moveToWorkspace(workspaceName: String)
    case createWorkspace
    case sidebarHover
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

    var preview: WindowTabDropPreviewViewModel {
        WindowTabDropPreviewViewModel(
            frame: previewRect.toAppKitScreenRect,
            title: title,
            subtitle: subtitle,
            style: previewStyle,
        )
    }
}

@MainActor
private func workspaceSidebarCursorPreviewRect(at mouseLocation: CGPoint) -> Rect {
    let width: CGFloat = 176
    let height: CGFloat = 40
    return Rect(
        topLeftX: mouseLocation.x + 16,
        topLeftY: mouseLocation.y - height - 12,
        width: width,
        height: height,
    )
}

@MainActor
private func sidebarDragSourceTitle(for sourceWindow: Window) -> String {
    let moveNode = sourceWindow.moveNode
    if moveNode is TilingContainer {
        let windowCount = max(moveNode.allLeafWindowsRecursive.count, 1)
        return "Tab Group • \(windowCount) windows"
    }
    return sidebarDisplayLabel(for: sourceWindow)
}

@MainActor
private func updateSidebarDragFeedback(sourceWindow: Window, destination: WindowDragIntentDestination?) {
    guard let destination, destination.previewStyle == .sidebarWorkspaceMove else {
        let hadPinnedWindow = hasPinnedDraggedWindow()
        setPinnedDraggedWindowId(nil)
        if TrayMenuModel.shared.workspaceSidebarDropPreview != nil {
            TrayMenuModel.shared.workspaceSidebarDropPreview = nil
        }
        if hadPinnedWindow {
            scheduleRefreshSession(.globalObserver("sidebarGhostExit"), optimisticallyPreLayoutWorkspaces: true)
        }
        return
    }

    let moveNode = sourceWindow.moveNode
    let isTabGroup = moveNode is TilingContainer
    let windowCount = max(moveNode.allLeafWindowsRecursive.count, 1)
    let targetWorkspaceName: String? = switch destination.kind {
        case .moveToWorkspace(let workspaceName): workspaceName
        case .createWorkspace: nil
        case .sidebarHover, .tabStack, .detachTab, .swap: nil
    }
    if case .moveToWorkspace = destination.kind {
        TrayMenuModel.shared.workspaceSidebarDropPreview = WorkspaceSidebarDropPreviewViewModel(
            sourceWindowId: sourceWindow.windowId,
            label: sidebarDisplayLabel(for: sourceWindow),
            targetWorkspaceName: targetWorkspaceName,
            targetsNewWorkspace: false,
            isTabGroup: isTabGroup,
            windowCount: windowCount,
        )
    } else if destination.kind == .createWorkspace {
        TrayMenuModel.shared.workspaceSidebarDropPreview = WorkspaceSidebarDropPreviewViewModel(
            sourceWindowId: sourceWindow.windowId,
            label: sidebarDisplayLabel(for: sourceWindow),
            targetWorkspaceName: nil,
            targetsNewWorkspace: true,
            isTabGroup: isTabGroup,
            windowCount: windowCount,
        )
    } else if TrayMenuModel.shared.workspaceSidebarDropPreview != nil {
        TrayMenuModel.shared.workspaceSidebarDropPreview = nil
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
private func currentWindowTabDropDestination(sourceWindow: Window, mouseLocation: CGPoint) -> WindowDragIntentDestination? {
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    return mouseLocation.findWindowTabDropDestination(in: targetWorkspace.rootTilingContainer, excluding: sourceWindow)
}

@MainActor
private func currentSidebarWorkspaceDropDestination(sourceWindow: Window, mouseLocation: CGPoint) -> WindowDragIntentDestination? {
    let sourceLabel = sidebarDragSourceTitle(for: sourceWindow)
    if let target = workspaceSidebarDropTarget(at: mouseLocation) {
        switch target.kind {
            case .workspace(let workspaceName):
                if sourceWindow.nodeWorkspace?.name != workspaceName {
                    return WindowDragIntentDestination(
                        kind: .moveToWorkspace(workspaceName: workspaceName),
                        previewRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                        interactionRect: target.rect.expanded(left: 14, right: 14, top: 12, bottom: 12),
                        title: sourceLabel,
                        subtitle: "Drop to send this item to \(workspaceName)",
                        previewStyle: .sidebarWorkspaceMove,
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
    guard let destination = currentWindowDragIntentDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation) else {
        updateSidebarDragFeedback(sourceWindow: sourceWindow, destination: nil)
        clearPendingWindowDragIntent()
        return false
    }
    updateSidebarDragFeedback(sourceWindow: sourceWindow, destination: destination)
    return setPendingWindowDragIntent(sourceWindowId: sourceWindow.windowId, destination: destination)
}

@MainActor
func updatePendingDetachedTabIntent(sourceWindow: Window, mouseLocation: CGPoint, origin: TabDetachOrigin) -> Bool {
    guard let destination = currentTabDetachDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation, origin: origin) else {
        clearPendingWindowDragIntent()
        return false
    }
    return setPendingWindowDragIntent(sourceWindowId: sourceWindow.windowId, destination: destination)
}

@MainActor
func refreshPendingWindowDragIntentFromGlobalMouseDrag() {
    guard let windowId = currentlyManipulatedWithMouseWindowId,
          let sourceWindow = Window.get(byId: windowId)
    else { return }
    _ = updatePendingWindowDragIntent(sourceWindow: sourceWindow, mouseLocation: mouseLocation)
}

@MainActor
private func setPendingWindowDragIntent(sourceWindowId: UInt32, destination: WindowDragIntentDestination) -> Bool {
    if let pendingWindowDragIntent,
       pendingWindowDragIntent.sourceWindowId == sourceWindowId,
       pendingWindowDragIntent.kind == destination.kind,
       pendingWindowDragIntent.title == destination.title,
       pendingWindowDragIntent.subtitle == destination.subtitle,
       pendingWindowDragIntent.previewRect.isEqual(to: destination.previewRect),
       pendingWindowDragIntent.interactionRect.isEqual(to: destination.interactionRect)
    {
        return true
    }

    pendingWindowDragIntent = PendingWindowDragIntent(
        sourceWindowId: sourceWindowId,
        kind: destination.kind,
        previewRect: destination.previewRect,
        interactionRect: destination.interactionRect,
        title: destination.title,
        subtitle: destination.subtitle,
        previewStyle: destination.previewStyle,
    )
    WindowTabDropPreviewPanel.shared.show(destination.preview)
    return true
}

@MainActor
func clearPendingWindowDragIntent() {
    pendingWindowDragIntent = nil
    setPinnedDraggedWindowId(nil)
    TrayMenuModel.shared.workspaceSidebarDropPreview = nil
    WindowTabDropPreviewPanel.shared.hide()
}

@MainActor
func applyPendingWindowDragIntentIfPossible() -> Bool {
    defer { clearPendingWindowDragIntent() }
    guard let pendingWindowDragIntent,
          let sourceWindow = Window.get(byId: pendingWindowDragIntent.sourceWindowId),
          pendingWindowDragIntent.interactionRect.contains(mouseLocation)
    else { return false }
    switch pendingWindowDragIntent.kind {
        case .tabStack(let targetWindowId):
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
            swapWindows(sourceWindow, targetWindow)
            return true
        case .moveToWorkspace(let workspaceName):
            let targetWorkspace = Workspace.get(byName: workspaceName)
            resetClosedWindowsCache()
            applyWorkspaceMove(sourceWindow: sourceWindow, mouseLocation: mouseLocation, targetWorkspace: targetWorkspace)
            return true
        case .createWorkspace:
            resetClosedWindowsCache()
            return createWorkspaceFromSidebarDrag(sourceWindow: sourceWindow)
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
private func currentWindowDragIntentDestination(sourceWindow: Window, mouseLocation: CGPoint) -> WindowDragIntentDestination? {
    if let sticky = pendingWindowDragIntent,
       sticky.sourceWindowId == sourceWindow.windowId,
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
        )
    }

    if let sidebarDestination = currentSidebarWorkspaceDropDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation) {
        return sidebarDestination
    }

    if config.windowTabs.enabled,
       let tabDestination = currentWindowTabDropDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation)
    {
        return tabDestination
    }

    if let detachDestination = currentTabDetachDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation, origin: .window) {
        return detachDestination
    }

    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    if targetWorkspace != sourceWindow.moveNode.nodeWorkspace {
        let previewRect = targetWorkspace.rootTilingContainer.lastAppliedLayoutPhysicalRect ?? targetWorkspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        return WindowDragIntentDestination(
            kind: .moveToWorkspace(workspaceName: targetWorkspace.name),
            previewRect: previewRect,
            interactionRect: previewRect,
            title: "Move Here",
            subtitle: "Drop to move this item to this workspace",
            previewStyle: .workspaceMove,
        )
    }

    return currentSwapDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation)
}

@MainActor
private func currentSwapDestination(sourceWindow: Window, mouseLocation: CGPoint) -> WindowDragIntentDestination? {
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    guard let targetWindow = mouseLocation.findIn(tree: targetWorkspace.rootTilingContainer, virtual: false) else { return nil }
    let sourceNode = sourceWindow.moveNode
    let targetNode = targetWindow.moveNode
    guard sourceNode != targetNode,
          let previewRect = targetNode.swapDropZoneRect,
          let interactionRect = targetNode.swapDropZoneRect?.expanded(left: 10, right: 10, top: 6, bottom: 10),
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
    )
}

@MainActor
private func applyWorkspaceMove(sourceWindow: Window, mouseLocation: CGPoint, targetWorkspace: Workspace) {
    let sourceNode = sourceWindow.moveNode
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
