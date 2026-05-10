import AppKit
import Common

func resizedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let notif = notif as String
    let windowId = ax.containingWindowId()
    Task { @MainActor in
        if shouldIgnoreAxObserverEventForPostDragSuppression(windowId: windowId, notif: notif) {
            return
        }
        if !config.enableWindowManagement {
            scheduleRefreshSession(.ax(notif))
            return
        }
        guard RunSessionGuard.isServerEnabled != nil else { return }
        guard let windowId, let window = Window.get(byId: windowId), try await isManipulatedWithMouse(window) else {
            scheduleRefreshSession(.ax(notif))
            return
        }
        guard window.parent is TilingContainer else {
            scheduleRefreshSession(.ax(notif))
            return
        }
        WindowMouseInteractionDriver.shared.startResize(windowId: window.windowId)
    }
}

@MainActor
func resetManipulatedWithMouseIfPossible() async throws {
    await WindowMouseInteractionDriver.shared.flushBeforeMouseUp()
    let didApplyPendingDragIntent = applyPendingWindowDragIntentIfPossible()
    let didApplyPendingUnmanagedSnap = applyPendingUnmanagedWindowSnapIfPossible()
    clearPendingWindowDragIntent()
    clearPendingUnmanagedWindowSnap()
    if currentlyManipulatedWithMouseWindowId != nil || didApplyPendingDragIntent || didApplyPendingUnmanagedSnap {
        armGlobalPostDragAxObserverSuppression()
        cancelManipulatedWithMouseState()
        scheduleRefreshSession(.resetManipulatedWithMouse, optimisticallyPreLayoutWorkspaces: true)
    }
    WindowMouseInteractionDriver.shared.stop()
}

private let adaptiveWeightBeforeResizeWithMouseKey = TreeNodeUserDataKey<CGFloat>(key: "adaptiveWeightBeforeResizeWithMouseKey")

@MainActor
func resizeWithMouse(_ window: Window) async throws { // todo cover with tests
    syncClosedWindowsCacheToCurrentWorld()
    guard let parent = window.parent else { return }
    switch parent.cases {
        case .workspace, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return // Nothing to do for floating, or unconventional windows
        case .tilingContainer:
            guard let rect = try await window.getAxRect() else { return }
            WindowMouseInteractionDriver.shared.startResize(windowId: window.windowId)
            updateCompositedResizePreview(window, rect: rect)
    }
}

@MainActor
func updateCompositedResizePreview(_ window: Window, rect: Rect) {
    syncClosedWindowsCacheToCurrentWorld()
    WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction()
    guard let workspace = window.nodeWorkspace,
          workspace.isVisible,
          let weightMap = proposedResizeWeightMap(window, rect: rect)
    else {
        WindowResizePreviewPanel.shared.hide()
        return
    }
    let items = windowResizePreviewItems(
        in: workspace,
        weightMap: weightMap,
        excludingActiveWindowId: window.windowId,
    )
    guard !items.isEmpty else {
        WindowResizePreviewPanel.shared.hide()
        return
    }
    currentlyManipulatedWithMouseWindowId = window.windowId
    setCurrentMouseManipulationKind(.resize)
    clearPendingWindowDragIntent()
    WindowResizePreviewPanel.shared.show(items)
}

@MainActor
func applyResizeWithMouse(_ window: Window, rect: Rect) {
    syncClosedWindowsCacheToCurrentWorld()
    guard let weightMap = proposedResizeWeightMap(window, rect: rect) else { return }
    for change in weightMap.changes {
        change.node.setWeight(change.orientation, change.weight)
    }
    currentlyManipulatedWithMouseWindowId = window.windowId
    setCurrentMouseManipulationKind(.resize)
    clearPendingWindowDragIntent()
}

struct WindowResizeWeightChange {
    let node: TreeNode
    let orientation: Orientation
    let weight: CGFloat
}

struct WindowResizePreviewWeightMap {
    private var weights: [WindowResizeWeightKey: CGFloat] = [:]
    private var nodes: [ObjectIdentifier: TreeNode] = [:]

    @MainActor
    var changes: [WindowResizeWeightChange] {
        weights.compactMap { key, weight in
            guard let node = nodes[key.nodeId] else { return nil }
            return WindowResizeWeightChange(node: node, orientation: key.orientation, weight: weight)
        }
    }

    mutating func set(_ weight: CGFloat, for node: TreeNode, orientation: Orientation) {
        let nodeId = ObjectIdentifier(node)
        weights[WindowResizeWeightKey(nodeId: nodeId, orientation: orientation)] = weight
        nodes[nodeId] = node
    }

    @MainActor
    func weight(for node: TreeNode, orientation: Orientation) -> CGFloat {
        weights[WindowResizeWeightKey(nodeId: ObjectIdentifier(node), orientation: orientation)] ??
            node.getWeight(orientation)
    }
}

private struct WindowResizeWeightKey: Hashable {
    let nodeId: ObjectIdentifier
    let orientation: Orientation
}

@MainActor
func proposedResizeWeightMap(_ window: Window, rect: Rect) -> WindowResizePreviewWeightMap? {
    guard window.parent is TilingContainer else { return nil }
    guard let lastAppliedLayoutRect = window.lastAppliedLayoutPhysicalRect else { return nil }
    var weightMap = WindowResizePreviewWeightMap()
    let (lParent, lOwnIndex) = window.closestParent(hasChildrenInDirection: .left, withLayout: .tiles) ?? (nil, nil)
    let (dParent, dOwnIndex) = window.closestParent(hasChildrenInDirection: .down, withLayout: .tiles) ?? (nil, nil)
    let (uParent, uOwnIndex) = window.closestParent(hasChildrenInDirection: .up, withLayout: .tiles) ?? (nil, nil)
    let (rParent, rOwnIndex) = window.closestParent(hasChildrenInDirection: .right, withLayout: .tiles) ?? (nil, nil)
    let table: [(CGFloat, TilingContainer?, Int?, Int?)] = [
        (lastAppliedLayoutRect.minX - rect.minX, lParent, 0,                        lOwnIndex),               // Horizontal, to the left of the window
        (rect.maxY - lastAppliedLayoutRect.maxY, dParent, dOwnIndex.map { $0 + 1 }, dParent?.children.count), // Vertical, to the down of the window
        (lastAppliedLayoutRect.minY - rect.minY, uParent, 0,                        uOwnIndex),               // Vertical, to the up of the window
        (rect.maxX - lastAppliedLayoutRect.maxX, rParent, rOwnIndex.map { $0 + 1 }, rParent?.children.count), // Horizontal, to the right of the window
    ]
    for (diff, parent, startIndex, pastTheEndIndex) in table {
        if let parent, let startIndex, let pastTheEndIndex, pastTheEndIndex - startIndex > 0 && abs(diff) > 5 { // 5 pixels should be enough to fight with accumulated floating precision error
            let siblingDiff = diff.div(pastTheEndIndex - startIndex).orDie()
            let orientation = parent.orientation

            window.parentsWithSelf.lazy
                .prefix(while: { $0 != parent })
                .filter {
                    let parent = $0.parent as? TilingContainer
                    return parent?.orientation == orientation && parent?.layout == .tiles
                }
                .forEach { weightMap.set($0.getWeightBeforeResize(orientation) + diff, for: $0, orientation: orientation) }
            for sibling in parent.children[startIndex ..< pastTheEndIndex] {
                weightMap.set(sibling.getWeightBeforeResize(orientation) - siblingDiff, for: sibling, orientation: orientation)
            }
        }
    }
    return weightMap
}

extension TreeNode {
    @MainActor
    func getWeightBeforeResize(_ orientation: Orientation) -> CGFloat {
        let currentWeight = getWeight(orientation) // Check assertions
        return getUserData(key: adaptiveWeightBeforeResizeWithMouseKey)
            ?? (lastAppliedLayoutVirtualRect?.getDimension(orientation) ?? currentWeight)
            .also { putUserData(key: adaptiveWeightBeforeResizeWithMouseKey, data: $0) }
    }

    func resetResizeWeightBeforeResizeRecursive() {
        cleanUserData(key: adaptiveWeightBeforeResizeWithMouseKey)
        for child in children {
            child.resetResizeWeightBeforeResizeRecursive()
        }
    }
}
