import AppKit
import Common

@MainActor
func unbindAndGetBindingDataForNewWindow(_ windowId: UInt32, _ macApp: MacApp, _ workspace: Workspace, window: Window?) async throws -> BindingData {
    let windowLevel = getWindowLevel(for: windowId)
    return switch try await macApp.getAxUiElementWindowType(windowId, windowLevel) {
        case .popup: BindingData(parent: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .dialog: BindingData(parent: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .window: bindingDataForNewTilingWindow(workspace, window: window)
    }
}

@MainActor
func bindingDataForNewTilingWindow(_ workspace: Workspace, window: Window?) -> BindingData {
    window?.unbindFromParent()
    if let tabGroupBinding = autoAddNewWindowToFocusedTabGroupBinding(workspace) {
        return tabGroupBinding
    }
    guard let mruWindow = workspace.mostRecentWindowRecursive,
          let tilingParent = mruWindow.parent as? TilingContainer
    else {
        return BindingData(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
    if tilingParent.layout == .tabGroup {
        return bindingDataAfterTabGroup(workspace: workspace, tabGroup: tilingParent)
    }
    return BindingData(parent: tilingParent, adaptiveWeight: WEIGHT_AUTO, index: mruWindow.ownIndex.orDie() + 1)
}

@MainActor
private func autoAddNewWindowToFocusedTabGroupBinding(_ workspace: Workspace) -> BindingData? {
    guard config.autoAddNewWindowsToTabGroup,
          let focusedWindow = focus.windowOrNil,
          focusedWindow.nodeWorkspace == workspace,
          let tabGroup = focusedWindow.parent as? TilingContainer,
          tabGroup.layout == .tabGroup
    else { return nil }
    return BindingData(parent: tabGroup, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
}

@MainActor
private func bindingDataAfterTabGroup(workspace: Workspace, tabGroup: TilingContainer) -> BindingData {
    var insertionAnchor: TreeNode = tabGroup
    var insertionParent: NonLeafTreeNodeObject = tabGroup.parent.orDie()
    while let parent = insertionParent as? TilingContainer, parent.layout == .tabGroup {
        insertionAnchor = parent
        insertionParent = parent.parent.orDie()
    }
    switch insertionParent.cases {
        case .tilingContainer(let parent):
            return BindingData(parent: parent, adaptiveWeight: WEIGHT_AUTO, index: insertionAnchor.ownIndex.orDie() + 1)
        case .workspace:
            ensureTabGroupAnchorHasWorkspaceRootContainer(workspace: workspace, insertionAnchor: insertionAnchor, tabGroup: tabGroup)
            return BindingData(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer:
            die("Impossible insertion parent for tiling window")
    }
}

@MainActor
private func ensureTabGroupAnchorHasWorkspaceRootContainer(
    workspace: Workspace,
    insertionAnchor: TreeNode,
    tabGroup: TilingContainer,
) {
    let previousRoot = workspace.rootTilingContainer
    guard previousRoot === insertionAnchor else { return }
    previousRoot.unbindFromParent()
    _ = TilingContainer(parent: workspace, adaptiveWeight: WEIGHT_AUTO, tabGroup.orientation.opposite, .tiles, index: 0)
    previousRoot.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: 0)
}
