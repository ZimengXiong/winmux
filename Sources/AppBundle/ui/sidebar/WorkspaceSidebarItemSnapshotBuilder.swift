@MainActor
func buildWorkspaceSidebarItems(
    for workspace: Workspace,
    currentFocus: LiveFocus,
) async -> [WorkspaceSidebarItemViewModel] {
    var items = await buildWorkspaceSidebarItems(
        from: workspace.rootTilingContainer,
        workspaceName: workspace.name,
        currentFocus: currentFocus,
    )
    for floatingWindow in workspace.floatingWindows where floatingWindow.isBound {
        items.append(.init(kind: .window(await makeWorkspaceSidebarWindowViewModel(
            for: floatingWindow,
            workspaceName: workspace.name,
            currentFocus: currentFocus,
        ))))
    }
    return items
}
