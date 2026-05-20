import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarProjectPager {
    @ViewBuilder
    var compactProjectIndicator: some View {
        if let selectedProject, let currentIndex {
            projectDot(selectedProject, index: currentIndex)
            .frame(width: sectionWidth, height: workspaceSidebarPagerHeight, alignment: .center)
        }
    }

    var projectDotTrack: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                projectDot(project, index: index)
            }
        }
        .padding(.horizontal, isCompact ? 2 : 0)
        .frame(minHeight: workspaceSidebarPagerHeight, alignment: .leading)
    }

    @ViewBuilder
    var projectMenu: some View {
        projectMenuButton
            .frame(width: projectMenuWidth, height: workspaceSidebarPagerHeight, alignment: .trailing)
            .contextMenu {
                if let selectedProject {
                    projectContextMenuItems(for: selectedProject)
                }
            }
    }

    var projectControls: some View {
        HStack(alignment: .center, spacing: footerSpacing) {
            projectDotTrack
                .frame(width: projectTrackWidth, alignment: .leading)
            projectMenu
                .frame(width: projectMenuWidth, height: workspaceSidebarPagerHeight, alignment: .trailing)
        }
        .frame(width: sectionWidth, height: workspaceSidebarPagerHeight, alignment: .center)
    }

    private var projectMenuButton: some View {
        Button {
            isProjectMenuOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(selectedProject?.displayName ?? "Project")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(isHovered || isProjectMenuOpen ? 0.86 : 0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(isHovered || isProjectMenuOpen ? 0.86 : 0.72))
                    .rotationEffect(.degrees(isProjectMenuOpen ? 180 : 0))
            }
            .padding(.horizontal, 6)
            .frame(height: workspaceSidebarDropdownHeight)
            .background {
                RoundedRectangle(cornerRadius: workspaceSidebarPlateCornerRadius, style: .continuous)
                    .fill(isProjectMenuOpen ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: workspaceSidebarPlateCornerRadius, style: .continuous)
                    .strokeBorder(isProjectMenuOpen ? Color.white.opacity(0.14) : Color.white.opacity(0.08), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .frame(height: workspaceSidebarPagerHeight, alignment: .center)
    }

    @ViewBuilder
    var projectPopup: some View {
        if isProjectMenuOpen {
            WorkspaceSidebarProjectPopup(
                projects: projects,
                selectedProjectId: selectedProjectId,
                onSelect: { projectId in
                    onSelectProject(projectId)
                    isProjectMenuOpen = false
                },
                onCreate: {
                    onCreateProject()
                    isProjectMenuOpen = false
                },
                onRename: { project in
                    isProjectMenuOpen = false
                },
                onSetColor: onSetProjectColor,
                onDelete: { project in
                    onDeleteProject(project)
                    isProjectMenuOpen = false
                },
                menuWidth: 148,
            )
            .frame(width: 148)
            .offset(y: -(workspaceSidebarPagerHeight + workspaceSidebarSectionGap))
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)),
                removal: .opacity,
            ))
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.88), value: isProjectMenuOpen)
            .zIndex(100)
        }
    }

    @ViewBuilder
    func projectContextMenuItems(for project: WorkspaceSidebarProjectViewModel) -> some View {
        Menu("Color") {
            let selectedColorHex = project.colorHex.flatMap(normalizedWorkspaceSidebarColorHex)
            Button {
                onSetProjectColor(project, nil)
            } label: {
                Label {
                    Text("Auto")
                } icon: {
                    Image(nsImage: workspaceSidebarAutomaticColorSwatchImage(isSelected: selectedColorHex == nil))
                }
            }
            Divider()
            ForEach(workspaceSidebarProjectColorPresets) { preset in
                Button {
                    onSetProjectColor(project, preset.hex)
                } label: {
                    Label {
                        Text(preset.name)
                    } icon: {
                        Image(nsImage: workspaceSidebarProjectColorSwatchImage(
                            hex: preset.hex,
                            isSelected: selectedColorHex == preset.hex,
                        ))
                    }
                }
            }
        }
        Button(role: .destructive) {
            onDeleteProject(project)
        } label: {
            Text("Delete Project")
        }
        .disabled(!canDeleteWorkspaceProject(project.id))
    }
}
