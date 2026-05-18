@MainActor
func buildWorkspaceSidebarItems(
    from node: TreeNode,
    workspaceName: String,
    currentFocus: LiveFocus,
) async -> [WorkspaceSidebarItemViewModel] {
    switch node.nodeCases {
        case .window(let window):
            guard window.isBound else { return [] }
            return [.init(kind: .window(await makeWorkspaceSidebarWindowViewModel(
                for: window,
                workspaceName: workspaceName,
                currentFocus: currentFocus,
            )))]
        case .tilingContainer(let container):
            return await buildWorkspaceSidebarContainerItems(
                container,
                workspaceName: workspaceName,
                currentFocus: currentFocus,
            )
        case .workspace(let workspace):
            return await buildWorkspaceSidebarItems(
                from: workspace.rootTilingContainer,
                workspaceName: workspaceName,
                currentFocus: currentFocus,
            )
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return []
    }
}

@MainActor
func buildWorkspaceSidebarContainerItems(
    _ container: TilingContainer,
    workspaceName: String,
    currentFocus: LiveFocus,
) async -> [WorkspaceSidebarItemViewModel] {
    if container.layout == .tabGroup, container.children.count > 1 {
        let group = await makeWorkspaceSidebarTabGroupViewModel(
            for: container,
            workspaceName: workspaceName,
            currentFocus: currentFocus,
        )
        return group.map { [.init(kind: .tabGroup($0))] } ?? []
    }
    var items: [WorkspaceSidebarItemViewModel] = []
    for child in container.children {
        items.append(contentsOf: await buildWorkspaceSidebarItems(
            from: child,
            workspaceName: workspaceName,
            currentFocus: currentFocus,
        ))
    }
    return items
}
