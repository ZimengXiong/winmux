import AppKit
import Common

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
        return workspaceInsertBindingData(targetNode: targetNode, targetParent: targetParent, targetRect: targetRect, mouseLocation: mouseLocation)
    }

    if targetNode === targetWorkspace.rootTilingContainer {
        return workspaceRootInsertBindingData(targetWorkspace: targetWorkspace, targetNode: targetNode, mouseLocation: mouseLocation)
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
    workspaceSiblingInsertionRoot(workspace, orientation: nil)
}

@MainActor
func workspaceSiblingInsertionRoot(_ workspace: Workspace, orientation: Orientation?) -> TilingContainer {
    let root = workspace.rootTilingContainer
    guard !root.children.isEmpty else {
        if let orientation, root.orientation != orientation {
            root.changeOrientation(orientation)
        }
        return root
    }
    guard root.layout == .tabGroup || orientation.map({ root.orientation != $0 }) == true else { return root }

    let previousRoot = root
    previousRoot.unbindFromParent()
    _ = TilingContainer(
        parent: workspace,
        adaptiveWeight: WEIGHT_AUTO,
        orientation ?? previousRoot.orientation.opposite,
        .tiles,
        index: 0,
    )
    previousRoot.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: 0)
    return workspace.rootTilingContainer
}

@MainActor
private func workspaceInsertBindingData(
    targetNode: TreeNode,
    targetParent: TilingContainer,
    targetRect: Rect,
    mouseLocation: CGPoint,
) -> BindingData {
    let index = mouseLocation.getProjection(targetParent.orientation) >= targetRect.center.getProjection(targetParent.orientation)
        ? targetNode.ownIndex.orDie() + 1
        : targetNode.ownIndex.orDie()
    return BindingData(
        parent: targetParent,
        adaptiveWeight: WEIGHT_AUTO,
        index: index,
    )
}

@MainActor
private func workspaceRootInsertBindingData(
    targetWorkspace: Workspace,
    targetNode: TreeNode,
    mouseLocation: CGPoint,
) -> BindingData {
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
