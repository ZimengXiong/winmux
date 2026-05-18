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
        HStack(spacing: workspaceSidebarHeaderSpacing) {
            Text(workspace.displayName)
                .font(.system(size: 15, weight: workspace.isFocused ? .bold : .semibold))
                .foregroundStyle(workspace.isFocused ? Color.white : Color.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if !workspace.items.isEmpty {
                Text("\(workspace.items.count)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .padding(.leading, workspaceSidebarHeaderRowLeadingPadding)
        .padding(.trailing, workspaceSidebarRowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
