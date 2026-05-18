import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func handleSectionClick() {
        if shouldHandleWorkspaceSidebarActivation(
            isEditing: isEditingName,
            isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()
        ) {
            focusWorkspaceFromSidebar(workspace.name)
        }
    }

    func beginInlineRename() {
        WorkspaceSidebarPanel.shared.beginInlineTextEditing()
        isEditingName = true
        editingNameDraft = workspace.displayName
    }

    func commitInlineRename() {
        guard isEditingName else { return }
        let trimmed = editingNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingName = false
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
        guard !trimmed.isEmpty, trimmed != workspace.displayName else { return }
        renameWorkspaceFromSidebar(workspace, displayName: trimmed)
    }

    func cancelInlineRename() {
        isEditingName = false
        editingNameDraft = ""
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
    }
}
