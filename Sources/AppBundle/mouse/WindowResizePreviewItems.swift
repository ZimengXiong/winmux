import AppKit
import Common

@MainActor
func windowResizePreviewItems(
    in workspace: Workspace,
    weightMap: WindowResizePreviewWeightMap,
    excludingActiveWindowId activeWindowId: UInt32?,
) -> [WindowResizePreviewItem] {
    guard !workspace.isEffectivelyEmpty else { return [] }
    let rect = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
    let context = WindowResizePreviewLayoutContext(workspace: workspace, weightMap: weightMap)
    var items = windowResizePreviewItems(
        node: workspace.rootTilingContainer,
        point: rect.topLeftCorner,
        width: rect.width,
        height: rect.height - 1,
        virtual: rect,
        context: context,
        activeWindowId: activeWindowId,
    )
    for window in workspace.floatingWindows where window.isBound {
        guard window.windowId != activeWindowId else { continue }
        guard let rect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect,
              rect.width > 0,
              rect.height > 0
        else { continue }
        items.append(WindowResizePreviewItem(window: window, rect: rect))
    }
    return items
}

@MainActor
func windowResizePreviewItems(
    node: TreeNode,
    point: CGPoint,
    width: CGFloat,
    height: CGFloat,
    virtual: Rect,
    context: WindowResizePreviewLayoutContext,
    activeWindowId: UInt32?,
) -> [WindowResizePreviewItem] {
    let physicalRect = Rect(
        topLeftX: point.x,
        topLeftY: point.y,
        width: max(width, 0),
        height: max(height, 0),
    )
    switch node.nodeCases {
        case .workspace(let workspace):
            return windowResizePreviewItems(
                node: workspace.rootTilingContainer,
                point: point,
                width: width,
                height: height,
                virtual: virtual,
                context: context,
                activeWindowId: activeWindowId,
            )
        case .window(let window):
            guard window.windowId != activeWindowId else { return [] }
            guard physicalRect.width > 0, physicalRect.height > 0 else { return [] }
            return [WindowResizePreviewItem(window: window, rect: physicalRect)]
        case .tilingContainer(let container):
            return windowResizePreviewContainerItems(
                container: container,
                physicalRect: physicalRect,
                point: point,
                width: width,
                height: height,
                virtual: virtual,
                context: context,
                activeWindowId: activeWindowId,
            )
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return []
    }
}

@MainActor
private func windowResizePreviewContainerItems(
    container: TilingContainer,
    physicalRect: Rect,
    point: CGPoint,
    width: CGFloat,
    height: CGFloat,
    virtual: Rect,
    context: WindowResizePreviewLayoutContext,
    activeWindowId: UInt32?,
) -> [WindowResizePreviewItem] {
    if container.usesWindowTabBehavior {
        if let activeWindowId, container.containsLeafWindow(withId: activeWindowId) {
            return []
        }
        guard physicalRect.width > 0, physicalRect.height > 0 else { return [] }
        return [WindowResizePreviewItem(tabGroup: container, rect: physicalRect)]
    }
    switch container.layout {
        case .tiles:
            return windowResizePreviewTileItems(
                container: container,
                point: point,
                width: width,
                height: height,
                virtual: virtual,
                context: context,
                activeWindowId: activeWindowId,
            )
        case .tabGroup:
            return windowResizePreviewTabGroupItems(
                container: container,
                point: point,
                width: width,
                height: height,
                virtual: virtual,
                context: context,
                activeWindowId: activeWindowId,
            )
    }
}
