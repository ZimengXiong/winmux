import SwiftUI

extension WorkspaceSidebarProjectPager {
    @ViewBuilder
    func projectDot(
        _ project: WorkspaceSidebarProjectViewModel,
        index: Int,
    ) -> some View {
        let isCurrent = index == currentIndex
        let isPressed = pressedProjectId == project.id
        let isDotHovered = hoveredProjectDotId == project.id
        let projectColor = workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex)
        Button {
            projectTrackScrollTargetId = project.id
            onSelectProject(project.id)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isDotHovered || isPressed ? projectColor.opacity(0.14) : Color.clear)
                    .frame(width: 34, height: 22)
                Capsule(style: .continuous)
                    .fill(isCurrent ? projectColor.opacity(0.86) : projectColor.opacity(isDotHovered ? 0.58 : (isHovered ? 0.44 : 0.32)))
                    .frame(width: isCurrent ? 28 : 13, height: isCompact ? 10 : 9)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isCurrent ? projectColor.opacity(0.94) : projectColor.opacity(isDotHovered ? 0.70 : (isHovered ? 0.54 : 0.36)),
                                lineWidth: isDotHovered || isCurrent ? 0.8 : 0.5,
                            )
                    }
                }
                .scaleEffect(isPressed ? 0.92 : 1, anchor: .center)
                .frame(width: 36, height: workspaceSidebarProjectDotFrameHeight, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(project.displayName)
        .help(project.displayName)
        .onHover { hovering in
            hoveredProjectDotId = hovering ? project.id : (hoveredProjectDotId == project.id ? nil : hoveredProjectDotId)
        }
        .contextMenu {
            projectContextMenuItems(for: project)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressedProjectId = project.id }
                .onEnded { _ in pressedProjectId = nil },
        )
        .animation(.easeOut(duration: 0.18), value: isCurrent)
        .animation(.easeOut(duration: 0.14), value: isDotHovered)
        .animation(.easeOut(duration: 0.14), value: isPressed)
    }
}
