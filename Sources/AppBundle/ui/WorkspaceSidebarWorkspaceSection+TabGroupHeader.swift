import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func tabGroupHeaderButton(_ group: WorkspaceSidebarTabGroupViewModel) -> some View {
        Button {
            guard allowsWorkspaceActivation else { return }
            guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
            if isInUseOnOtherDisplay {
                activeInUseOverrideWorkspaceName = workspace.name
                return
            }
            activeInUseOverrideWorkspaceName = nil
            actions.send(.selectWindow(group.representativeWindowId))
        } label: {
            WorkspaceSidebarWindowRow(
                title: group.title.isEmpty ? "Tab Group" : group.title,
                badge: group.windowCount > 1 ? "\(group.windowCount)" : nil,
                isFocused: group.isFocused,
                suppressFocusedStyle: isSearchFiltering,
                rowHeight: rowHeight,
                isHovered: hoveredTabGroupId == group.representativeWindowId || selectedSearchTarget == .window(group.representativeWindowId),
                style: .tabGroupHeader,
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
            onChanged: { actions.tabGroupDragChanged(group.representativeWindowId, $0) },
            onEnded: { actions.tabGroupDragEnded(group.representativeWindowId, $0) },
        ))
        .workspaceSidebarDrag(enabled: true) {
            WorkspaceSidebarDragPayload.tabGroup(group.representativeWindowId).itemProvider
        }
        .onHover { hover in
            hoveredTabGroupId = hover ? group.representativeWindowId :
                (hoveredTabGroupId == group.representativeWindowId ? nil : hoveredTabGroupId)
        }
        .opacity(1)
    }
}
