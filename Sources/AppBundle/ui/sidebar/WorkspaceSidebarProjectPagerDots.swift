import SwiftUI

extension WorkspaceSidebarProjectPager {
    @ViewBuilder
    func projectDot(
        _ project: WorkspaceSidebarProjectViewModel,
        index: Int,
    ) -> some View {
        let isCurrent = index == currentIndex
        let isDotHovered = hoveredProjectDotId == project.id
        let projectColor = workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex)
        Button {
            debugWorkspaceSidebarProjectLog(
                "dotButton project=\(project.id.rawValue) selected=\(selectedProjectId.rawValue) currentIndex=\(currentIndex?.description ?? "nil") compact=\(isCompact) projects=\(projects.map(\.id.rawValue))"
            )
            projectTrackScrollTargetId = project.id
            onSelectProject(project.id)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isDotHovered ? projectColor.opacity(0.14) : Color.clear)
                    .frame(width: 34, height: 22)
                Capsule(style: .continuous)
                    .fill(isCurrent ? Color.white.opacity(0.17) : projectColor.opacity(isDotHovered ? 0.58 : (isHovered ? 0.44 : 0.32)))
                    .frame(width: isCurrent ? 28 : 13, height: isCompact ? 10 : 9)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isCurrent ? Color.white.opacity(0.42) : projectColor.opacity(isDotHovered ? 0.70 : (isHovered ? 0.54 : 0.36)),
                                lineWidth: isDotHovered || isCurrent ? 0.8 : 0.5,
                            )
                    }
                    .overlay {
                        if isCurrent {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.18), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom,
                                    )
                                )
                                .padding(0.8)
                        }
                    }
                }
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
        .animation(.easeOut(duration: 0.14), value: isDotHovered)
    }
}
