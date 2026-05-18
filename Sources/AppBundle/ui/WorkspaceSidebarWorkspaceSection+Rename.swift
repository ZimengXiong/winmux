import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    var workspaceRenameEditor: some View {
        WorkspaceSidebarProjectRenameField(
            text: $editingNameDraft,
            focusId: "workspace:\(workspace.name)",
            alignment: .left,
            fontSize: 14,
            fontWeight: .semibold,
            onCommit: commitInlineRename,
            onCancel: cancelInlineRename,
        )
        .padding(.horizontal, 5)
        .frame(height: 24)
        .background(workspaceRenameEditorBackground)
        .padding(.leading, workspaceSidebarHeaderRowLeadingPadding)
        .padding(.trailing, workspaceSidebarRowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var workspaceRenameEditorBackground: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white.opacity(0.075))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(workspaceSidebarActiveWorkspaceTint.opacity(0.48), lineWidth: 0.6)
            }
    }
}
