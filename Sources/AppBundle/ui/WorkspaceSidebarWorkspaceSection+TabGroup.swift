import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func workspaceTabGroupView(_ group: WorkspaceSidebarTabGroupViewModel) -> some View {
        let isDragging = activeSidebarDragSourceWindowId == group.representativeWindowId
        let groupHoverId = UInt32.max - group.representativeWindowId
        return VStack(alignment: .leading, spacing: 1) {
            tabGroupHeaderButton(group, groupHoverId: groupHoverId)
            tabGroupTabs(group, isDragging: isDragging)
        }
        .padding(.vertical, 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: isDragging)
    }

    func tabGroupTabs(_ group: WorkspaceSidebarTabGroupViewModel, isDragging: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(group.tabs) { tab in
                workspaceWindowButton(tab, allowsDrag: true, subject: .window, leadingHitInset: 14)
            }
        }
        .opacity(isDragging ? 0.4 : 1)
    }
}
