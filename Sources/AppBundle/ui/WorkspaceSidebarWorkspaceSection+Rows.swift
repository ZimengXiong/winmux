import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    @ViewBuilder
    var windowRows: some View {
        let items = workspace.items.filter { item in
            !workspaceSidebarItemIsActiveDragSource(item, dragPreview: dragPreview)
        }
        if showsWindowRows, !items.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(items) { item in
                    workspaceItemView(item)
                }
            }
            .padding(.leading, workspaceSidebarWindowRowsLeadingIndent)
        }
    }

    @ViewBuilder
    func workspaceItemView(_ item: WorkspaceSidebarItemViewModel) -> some View {
        switch item.kind {
            case .window(let window):
                workspaceWindowButton(window, allowsDrag: true)
            case .tabGroup(let group):
                workspaceTabGroupView(group)
        }
    }

    @ViewBuilder
    var dropPreviewRow: some View {
        if dragPreview?.targetWorkspaceName == workspace.name {
            WorkspaceSidebarDropPreviewView(preview: dragPreview.orDie(), rowHeight: rowHeight)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
                removal: .identity,
            ))
        }
    }
}

private func workspaceSidebarItemIsActiveDragSource(
    _ item: WorkspaceSidebarItemViewModel,
    dragPreview: WorkspaceSidebarDropPreviewViewModel?,
) -> Bool {
    guard let dragPreview else { return false }
    switch item.kind {
        case .window(let window):
            return !dragPreview.isTabGroup && window.windowId == dragPreview.sourceWindowId
        case .tabGroup(let group):
            return dragPreview.isTabGroup && group.representativeWindowId == dragPreview.sourceWindowId
    }
}
