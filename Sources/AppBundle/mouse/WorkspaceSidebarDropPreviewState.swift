@MainActor
func setWorkspaceSidebarDropPreviewIfChanged(_ preview: WorkspaceSidebarDropPreviewViewModel?) {
    if TrayMenuModel.shared.workspaceSidebarDropPreview != preview {
        TrayMenuModel.shared.workspaceSidebarDropPreview = preview
        WorkspaceSidebarPanel.syncVisiblePanelModelsFromShared()
    }
}
