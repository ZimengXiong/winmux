import SwiftUI

struct WorkspaceSidebarProjectPopup: View {
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId
    let onSelect: (WorkspaceProjectId) -> Void
    let onCreate: () -> Void
    let onRename: (WorkspaceSidebarProjectViewModel) -> Void
    let onSetColor: (WorkspaceSidebarProjectViewModel, String?) -> Void
    let onDelete: (WorkspaceSidebarProjectViewModel) -> Void
    var showsCreateAction = true
    var allowsContextMenu = true
    var menuWidth: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: workspaceSidebarMenuRowSpacing) {
            ForEach(projects) { project in
                projectRow(project)
            }
            if showsCreateAction {
                divider
                newProjectButton
            }
        }
        .padding(workspaceSidebarMenuRowSpacing + 1)
        .frame(minWidth: menuWidth, idealWidth: menuWidth, maxWidth: menuWidth, alignment: .leading)
        .fixedSize(horizontal: menuWidth != nil, vertical: false)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 0.98)))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                }
        }
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 7)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func projectRow(_ project: WorkspaceSidebarProjectViewModel) -> some View {
        Button {
            onSelect(project.id)
        } label: {
            HStack(spacing: 8) {
                Text(project.displayName)
                    .font(.system(size: 12, weight: project.id == selectedProjectId ? .semibold : .medium))
                    .foregroundStyle(workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex))
                    .lineLimit(1)
                Spacer(minLength: 0)
                checkmark(isVisible: project.id == selectedProjectId)
            }
            .modifier(WorkspaceSidebarDropdownMenuRowStyle(isSelected: project.id == selectedProjectId))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if allowsContextMenu {
                projectContextMenuItems(for: project)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, workspaceSidebarDropdownPadding)
            .padding(.vertical, 1)
    }

    private var newProjectButton: some View {
        Button(action: onCreate) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 8)
                Text("New")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                checkmark(isVisible: false)
            }
            .foregroundStyle(Color.white.opacity(0.78))
            .modifier(WorkspaceSidebarDropdownMenuRowStyle(isSelected: false))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
