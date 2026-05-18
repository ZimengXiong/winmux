struct WorkspaceSidebarItemViewModel: Hashable, Identifiable {
    let kind: WorkspaceSidebarItemKind

    var id: String {
        switch kind {
            case .window(let window):
                "window:\(window.windowId)"
            case .tabGroup(let group):
                group.id
        }
    }
}

enum WorkspaceSidebarItemKind: Hashable {
    case window(WorkspaceSidebarWindowViewModel)
    case tabGroup(WorkspaceSidebarTabGroupViewModel)
}
