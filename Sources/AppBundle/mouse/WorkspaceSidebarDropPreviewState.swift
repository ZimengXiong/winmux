@MainActor
func setWorkspaceSidebarDropPreviewIfChanged(_ preview: WorkspaceSidebarDropPreviewViewModel?) {
    if TrayMenuModel.shared.setIfChanged(\.workspaceSidebarDropPreview, preview) {
        WorkspaceSidebarPanel.syncVisiblePanelModelsFromShared()
    }
}
