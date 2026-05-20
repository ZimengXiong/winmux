import AppKit
import Common

@MainActor
func dragSubjectNode(for sourceWindow: Window, subject: WindowDragSubject) -> TreeNode {
    switch subject {
        case .window: sourceWindow
        case .group: sourceWindow.moveNode
    }
}

@MainActor
func dragIntentTargetNode(
    sourceWindow: Window,
    targetWindow: Window,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> TreeNode {
    guard let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .tabGroup,
          targetWindow.parent === sourceParent
    else { return targetWindow.moveNode }

    if subject == .window, detachOrigin == .tabStrip {
        logWindowDragHitTestIfNeeded(
            signature: "self-tab-group-target:source=\(sourceWindow.windowId):target=\(targetWindow.windowId)",
            "windowDragTarget.selfTabGroup source=\(debugDescribe(sourceWindow)) target=\(debugDescribe(targetWindow)) chosen=\(debugDescribe(sourceParent)) reason=tab-strip-window-drag-over-own-tab-group"
        )
        return sourceParent
    }
    if subject == .group, detachOrigin != .tabStrip {
        return targetWindow
    }
    return targetWindow.moveNode
}

@MainActor
func allowsTabGroupSelfTargeting(sourceNode: TreeNode, targetNode: TreeNode) -> Bool {
    if let sourceTabGroup = sourceNode as? TilingContainer,
       sourceTabGroup.layout == .tabGroup,
       let targetWindow = targetNode as? Window,
       targetWindow.parent === sourceTabGroup
    {
        return true
    }
    guard let sourceTabGroup = sourceNode as? TilingContainer,
          sourceTabGroup.layout == .tabGroup
    else {
        return (sourceNode as? Window)?.parent === targetNode
    }
    return targetNode === sourceTabGroup
}

@MainActor
func isBlockedByDragTargetContainment(sourceNode: TreeNode, targetNode: TreeNode) -> Bool {
    if sourceNode == targetNode {
        return true
    }
    if sourceNode.parentsWithSelf.contains(targetNode) && !allowsTabGroupSelfTargeting(sourceNode: sourceNode, targetNode: targetNode) {
        return true
    }
    if targetNode.parentsWithSelf.contains(sourceNode) && !allowsTabGroupSelfTargeting(sourceNode: sourceNode, targetNode: targetNode) {
        return true
    }
    return false
}

@MainActor
func isInvalidGroupSelfTarget(sourceNode: TreeNode, targetNode: TreeNode, subject: WindowDragSubject) -> Bool {
    guard subject == .group else { return false }
    return targetNode.parentsWithSelf.contains(sourceNode)
}

@MainActor
func sidebarDragSourceTitle(for sourceWindow: Window, subject: WindowDragSubject) -> String {
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
private func sidebarDragPreviewTabItems(for moveNode: TreeNode, isTabGroup: Bool) -> [WorkspaceSidebarDropPreviewTabItem] {
    guard isTabGroup else { return [] }
    return moveNode.allLeafWindowsRecursive.map { window in
        let appName = window.app.name ?? window.app.rawAppBundleId ?? "Window"
        return WorkspaceSidebarDropPreviewTabItem(
            title: cachedWindowTitle(for: window)?.takeIf { $0 != appName } ?? appName,
            appName: appName,
            appBundleIdentifier: window.app.rawAppBundleId,
            appBundlePath: window.app.bundlePath
        )
    }
}

@MainActor
func updateSidebarDragFeedback(sourceWindow: Window, subject: WindowDragSubject, destination: WindowDragIntentDestination?) {
    guard let destination, destination.previewStyle == .sidebarWorkspaceMove else {
        let hadPinnedWindow = hasPinnedDraggedWindow()
        setPinnedDraggedWindowId(nil)
        setWorkspaceSidebarDropPreviewIfChanged(nil)
        if WorkspaceSidebarPanel.shared.visibleScreenRectNormalized()?.contains(MousePointerTracker.shared.currentSample.point) == true {
            showWorkspaceSidebarDragCursorPreview(
                sourceWindow: sourceWindow,
                subject: subject,
                point: MousePointerTracker.shared.currentSample.point,
            )
        } else {
            WindowDragCursorProxyPanel.shared.hide()
        }
        if hadPinnedWindow {
            scheduleRefreshSession(.globalObserver("sidebarGhostExit"), optimisticallyPreLayoutWorkspaces: true)
        }
        return
    }

    let moveNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let isTabGroup = moveNode is TilingContainer
    let windowCount = max(moveNode.allLeafWindowsRecursive.count, 1)
    let sourceLabel = sidebarDragSourceTitle(for: sourceWindow, subject: subject)
    let appName = sourceWindow.app.name ?? sourceWindow.app.rawAppBundleId ?? "Window"
    let tabItems = sidebarDragPreviewTabItems(for: moveNode, isTabGroup: isTabGroup)
    let targetWorkspaceName: String? = switch destination.kind {
        case .moveToWorkspace(let workspaceName): workspaceName
        case .createWorkspace, .sidebarHover, .tabStack, .detachTab, .stackSplit, .swap: nil
    }
    if case .moveToWorkspace = destination.kind {
        setWorkspaceSidebarDropPreviewIfChanged(WorkspaceSidebarDropPreviewViewModel(
            sourceWindowId: sourceWindow.windowId,
            label: sourceLabel,
            appName: appName,
            appBundleIdentifier: sourceWindow.app.rawAppBundleId,
            appBundlePath: sourceWindow.app.bundlePath,
            targetWorkspaceName: targetWorkspaceName,
            targetsNewWorkspace: false,
            isTabGroup: isTabGroup,
            windowCount: windowCount,
            tabItems: tabItems,
        ))
    } else if destination.kind == .createWorkspace {
        setWorkspaceSidebarDropPreviewIfChanged(WorkspaceSidebarDropPreviewViewModel(
            sourceWindowId: sourceWindow.windowId,
            label: sourceLabel,
            appName: appName,
            appBundleIdentifier: sourceWindow.app.rawAppBundleId,
            appBundlePath: sourceWindow.app.bundlePath,
            targetWorkspaceName: nil,
            targetsNewWorkspace: true,
            isTabGroup: isTabGroup,
            windowCount: windowCount,
            tabItems: tabItems,
        ))
    } else {
        setWorkspaceSidebarDropPreviewIfChanged(nil)
    }

    setPinnedDraggedWindowId(nil)
    showWorkspaceSidebarDragCursorPreview(
        sourceWindow: sourceWindow,
        subject: subject,
        point: MousePointerTracker.shared.currentSample.point,
    )
}
