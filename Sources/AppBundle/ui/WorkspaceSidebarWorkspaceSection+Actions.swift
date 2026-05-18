import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func handleSectionClick() {
        if isInUseOnOtherDisplay {
            activeInUseOverrideWorkspaceName = workspace.name
            return
        }
        if shouldHandleWorkspaceSidebarActivation(
            isEditing: isEditingName,
            isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()
        ) {
            actions.send(.selectWorkspace(workspace.name))
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
        actions.send(.renameWorkspace(workspace.name, displayName: trimmed))
    }

    func cancelInlineRename() {
        isEditingName = false
        editingNameDraft = ""
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
    }
}
