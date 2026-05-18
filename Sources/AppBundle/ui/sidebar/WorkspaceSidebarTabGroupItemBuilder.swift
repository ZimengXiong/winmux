@MainActor
func makeWorkspaceSidebarTabGroupViewModel(
    for container: TilingContainer,
    workspaceName: String,
    currentFocus: LiveFocus,
) async -> WorkspaceSidebarTabGroupViewModel? {
    let representativeWindow = container.tabActiveWindow ?? container.mostRecentWindowRecursive ?? container.anyLeafWindowRecursive
    guard let representativeWindow else { return nil }
    let tabs = await buildWorkspaceSidebarTabItems(
        for: container,
        workspaceName: workspaceName,
        currentFocus: currentFocus,
    )
    guard !tabs.isEmpty else { return nil }
    return WorkspaceSidebarTabGroupViewModel(
        representativeWindowId: representativeWindow.windowId,
        workspaceName: workspaceName,
        title: sidebarDisplayLabel(for: representativeWindow),
        windowCount: container.allLeafWindowsRecursive.count,
        isFocused: representativeWindow.moveNode == currentFocus.windowOrNil?.moveNode,
        tabs: tabs,
    )
}

@MainActor
private func buildWorkspaceSidebarTabItems(
    for container: TilingContainer,
    workspaceName: String,
    currentFocus: LiveFocus,
) async -> [WorkspaceSidebarWindowViewModel] {
    var tabs: [WorkspaceSidebarWindowViewModel] = []
    for child in container.children {
        guard let representative = child.tabRepresentativeWindow ?? child.mostRecentWindowRecursive ?? child.anyLeafWindowRecursive,
              representative.isBound
        else { continue }
        tabs.append(await makeWorkspaceSidebarWindowViewModel(
            for: representative,
            workspaceName: workspaceName,
            currentFocus: currentFocus,
        ))
    }
    return tabs
}
