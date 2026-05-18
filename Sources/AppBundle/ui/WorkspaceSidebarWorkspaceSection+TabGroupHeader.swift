import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func tabGroupHeaderButton(_ group: WorkspaceSidebarTabGroupViewModel, groupHoverId: UInt32) -> some View {
        Button {
            guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
            if isInUseOnOtherDisplay {
                activeInUseOverrideWorkspaceName = workspace.name
                return
            }
            activeInUseOverrideWorkspaceName = nil
            actions.send(.selectWindow(group.representativeWindowId, fallbackWorkspace: group.workspaceName))
        } label: {
            WorkspaceSidebarWindowRow(
                title: group.title.isEmpty ? "Tab Group" : group.title,
                badge: group.windowCount > 1 ? "\(group.windowCount)" : nil,
                isFocused: group.isFocused,
                rowHeight: rowHeight,
                isHovered: hoveredWindowId == groupHoverId,
                style: .tabGroupHeader,
                hoverNamespace: rowHoverNamespace,
                appBundleIds: group.tabs.map(\.appBundleId),
                appBundlePaths: group.tabs.map(\.appBundlePath),
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(WorkspaceSidebarOptionalDragModifier(
            isEnabled: true,
            onChanged: { actions.tabGroupDragChanged(group.representativeWindowId) },
            onEnded: { actions.tabGroupDragEnded(group.representativeWindowId) },
        ))
        .workspaceSidebarDrag(enabled: true) {
            WorkspaceSidebarDragPayload.tabGroup(group.representativeWindowId).itemProvider
        }
        .onHover { hover in
            hoveredWindowId = nextWorkspaceSidebarHoveredWindowId(
                currentHoveredWindowId: hoveredWindowId,
                windowId: groupHoverId,
                isHovering: hover,
            )
        }
        .opacity(activeSidebarDragSourceWindowId == group.representativeWindowId ? 0.25 : 1)
        .scaleEffect(activeSidebarDragSourceWindowId == group.representativeWindowId ? 0.94 : 1)
    }
}
