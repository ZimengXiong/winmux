import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    var headerButton: some View {
        Button(action: handleSectionClick) {
            header
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var header: some View {
        Group {
            if isCompact {
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
                .font(.system(size: 15, weight: isActiveOnTargetMonitor ? .bold : .semibold))
                .foregroundStyle(isActiveOnTargetMonitor ? Color.white : Color.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            if let projectContextLabel, let projectContextColor {
                Text(projectContextLabel)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(projectContextColor.opacity(0.86))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background {
                        Capsule(style: .continuous)
                            .fill(projectContextColor.opacity(0.13))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(projectContextColor.opacity(0.24), lineWidth: 0.5)
                    }
            }
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
