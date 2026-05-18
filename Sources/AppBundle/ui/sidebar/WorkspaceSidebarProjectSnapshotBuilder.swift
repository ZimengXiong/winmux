@MainActor
func buildWorkspaceSidebarProjectViewModels() -> [WorkspaceSidebarProjectViewModel] {
    workspaceProjects().map {
        WorkspaceSidebarProjectViewModel(
            id: $0.id,
            displayName: $0.name,
            colorHex: config.workspaceSidebar.projectColors[$0.id.rawValue].flatMap(normalizedWorkspaceSidebarColorHex),
        )
    }
}
