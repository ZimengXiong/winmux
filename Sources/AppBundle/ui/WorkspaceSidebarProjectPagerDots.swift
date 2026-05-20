import SwiftUI

extension WorkspaceSidebarProjectPager {
    @ViewBuilder
    func projectDot(
        _ project: WorkspaceSidebarProjectViewModel,
        index: Int,
    ) -> some View {
        let isCurrent = index == currentIndex
        let isPressed = pressedProjectId == project.id
        let projectColor = workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex)
        Button {
            onSelectProject(project.id)
        } label: {
            Capsule(style: .continuous)
                .fill(isCurrent ? projectColor.opacity(0.82) : projectColor.opacity(isHovered ? 0.40 : 0.28))
                .frame(width: isCurrent ? 24 : 8, height: isCompact ? 9 : 7)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isCurrent ? projectColor.opacity(0.90) : projectColor.opacity(isHovered ? 0.50 : 0.32),
                            lineWidth: 0.5,
                        )
                }
                .shadow(color: isCurrent ? projectColor.opacity(0.18) : Color.clear, radius: 6, y: 1)
                .scaleEffect(isPressed ? 0.92 : 1, anchor: .center)
                .frame(width: 28, height: workspaceSidebarProjectDotFrameHeight, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(project.displayName)
        .help(project.displayName)
        .contextMenu {
            projectContextMenuItems(for: project)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressedProjectId = project.id }
                .onEnded { _ in pressedProjectId = nil },
        )
        .animation(.easeOut(duration: 0.18), value: isCurrent)
        .animation(.easeOut(duration: 0.14), value: isPressed)
    }
}
