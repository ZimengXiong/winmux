import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func workspaceWindowButton(
        _ window: WorkspaceSidebarWindowViewModel,
        allowsDrag: Bool,
        subject: WindowDragSubject = .window,
        leadingHitInset: CGFloat = 0,
    ) -> some View {
        Button {
            guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
            if isInUseOnOtherDisplay {
                activeInUseOverrideWorkspaceName = workspace.name
                return
            }
            activeInUseOverrideWorkspaceName = nil
            actions.send(.selectWindow(window.windowId, fallbackWorkspace: window.workspaceName))
        } label: {
            WorkspaceSidebarWindowRow(
                title: window.title ?? window.appName,
                badge: nil,
                isFocused: window.isFocused,
                rowHeight: rowHeight,
                isHovered: hoveredWindowId == window.windowId,
                style: leadingHitInset > 0 ? .tabGroupChild : .window,
                appBundleIds: [window.appBundleId],
                appBundlePaths: [window.appBundlePath],
            )
            .padding(.leading, leadingHitInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(WorkspaceSidebarOptionalDragModifier(
            isEnabled: allowsDrag,
            onChanged: { pointer in
                if subject == .group {
                    actions.tabGroupDragChanged(window.windowId, pointer)
                } else {
                    actions.windowDragChanged(window.windowId, pointer)
                }
            },
            onEnded: { pointer in
                if subject == .group {
                    actions.tabGroupDragEnded(window.windowId, pointer)
                } else {
                    actions.windowDragEnded(window.windowId, pointer)
                }
            },
        ))
        .workspaceSidebarDrag(enabled: allowsDrag) {
            WorkspaceSidebarDragPayload.window(window.windowId).itemProvider
        }
        .onHover { hover in
            hoveredWindowId = nextWorkspaceSidebarHoveredWindowId(
                currentHoveredWindowId: hoveredWindowId,
                windowId: window.windowId,
                isHovering: hover,
            )
        }
        .opacity(activeSidebarDragSourceWindowId == window.windowId ? 0.25 : 1)
        .scaleEffect(activeSidebarDragSourceWindowId == window.windowId ? 0.94 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: activeSidebarDragSourceWindowId == window.windowId)
    }
}
