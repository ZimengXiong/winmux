import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func workspaceTabGroupView(_ group: WorkspaceSidebarTabGroupViewModel) -> some View {
        let isDragging = activeSidebarDragSourceWindowId == group.representativeWindowId
        return VStack(alignment: .leading, spacing: 1) {
            tabGroupHeaderButton(group)
            tabGroupTabs(group, isDragging: isDragging)
        }
        .padding(.vertical, 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: isDragging)
    }

    func tabGroupTabs(_ group: WorkspaceSidebarTabGroupViewModel, isDragging: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(group.tabs) { tab in
                workspaceWindowButton(
                    tab,
                    allowsDrag: true,
                    subject: .window,
                    leadingHitInset: workspaceSidebarTabGroupChildLeadingIndent,
                )
            }
        }
        .opacity(isDragging ? 0.4 : 1)
    }
}
