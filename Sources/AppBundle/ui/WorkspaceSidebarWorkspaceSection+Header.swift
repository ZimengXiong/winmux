import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    var headerButton: some View {
        Button(action: handleSectionClick) {
            header
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { beginInlineRename() })
    }

    var header: some View {
        Group {
            if isEditingName && !isCompact {
                workspaceRenameEditor
            } else if isCompact {
                workspaceBadge
                    .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                expandedHeader
            }
        }
    }

    var expandedHeader: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(workspace.displayName)
                .font(.system(size: 14, weight: workspace.isFocused ? .bold : .semibold))
                .foregroundStyle(workspace.isFocused ? Color.white.opacity(0.96) : Color.white.opacity(0.86))
                .lineLimit(1)
            if let monitorName = workspace.monitorName, showsWindowRows {
                Text(monitorName)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .lineLimit(1)
            }
        }
        .padding(.leading, workspaceSidebarHeaderLeadingPadding)
        .padding(.trailing, workspaceSidebarRowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
