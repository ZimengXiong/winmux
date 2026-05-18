import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarProjectPager {
    func beginInlineRename(_ project: WorkspaceSidebarProjectViewModel) {
        if selectedProjectId != project.id {
            onSelectProject(project.id)
        }
        WorkspaceSidebarPanel.shared.beginInlineTextEditing()
        editingProjectId = project.id
        editingProjectDraft = project.displayName
    }

    func commitInlineRename(_ project: WorkspaceSidebarProjectViewModel) {
        guard editingProjectId == project.id else { return }
        let trimmed = editingProjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        editingProjectId = nil
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
        guard !trimmed.isEmpty, trimmed != project.displayName else { return }
        onRenameProject(project, trimmed)
    }

    func cancelInlineRename() {
        editingProjectId = nil
        editingProjectDraft = ""
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
    }

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
        if let selectedProject, editingProjectId == selectedProject.id {
            projectMenuInlineEditor(selectedProject)
        } else {
            projectMenuButton
            .frame(width: projectMenuWidth, height: workspaceSidebarPagerHeight, alignment: .trailing)
            .contextMenu {
                if let selectedProject {
                    projectContextMenuItems(for: selectedProject)
                }
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
                    beginInlineRename(project)
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
        Button("Rename Project") {
            beginInlineRename(project)
        }
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

    func projectMenuInlineEditor(_ project: WorkspaceSidebarProjectViewModel) -> some View {
        WorkspaceSidebarProjectRenameField(
            text: $editingProjectDraft,
            focusId: project.id.rawValue,
            alignment: .left,
            fontSize: 11.5,
            fontWeight: .semibold,
            onCommit: {
                commitInlineRename(project)
            },
            onCancel: cancelInlineRename,
        )
            .padding(.horizontal, 7)
            .frame(width: projectMenuWidth, height: 28, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 0.5)
                    }
            )
    }
}
