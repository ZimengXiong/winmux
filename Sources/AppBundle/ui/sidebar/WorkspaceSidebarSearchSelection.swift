enum WorkspaceSidebarSearchSelection: Hashable {
    case workspace(String)
    case window(UInt32)
}

func workspaceSidebarSearchSelections(
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
) -> [WorkspaceSidebarSearchSelection] {
    workspaces.flatMap { workspace in
        let itemSelections = workspace.items.flatMap { item -> [WorkspaceSidebarSearchSelection] in
            switch item.kind {
                case .window(let window):
                    return [.window(window.windowId)]
                case .tabGroup(let group):
                    return (group.searchVisibleTabs ?? group.tabs).map { .window($0.windowId) }
            }
        }
        return itemSelections.isEmpty ? [.workspace(workspace.name)] : itemSelections
    }
}
