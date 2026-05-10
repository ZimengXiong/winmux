import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarProjectPager {
    func beginInlineRename(_ project: WorkspaceSidebarProjectViewModel) {
        if selectedProjectId != project.id {
            selectWorkspaceSidebarProject(project.id)
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
        renameWorkspaceSidebarProject(project, displayName: trimmed)
    }

    func cancelInlineRename() {
        editingProjectId = nil
        editingProjectDraft = ""
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
    }

    @ViewBuilder
    var compactProjectIndicator: some View {
        if let selectedProject, let currentIndex {
            projectDot(
                selectedProject,
                index: currentIndex,
                swipeProgress: 1,
                edgeProgress: dotEdgeProgress(for: currentIndex),
            )
            .frame(width: sectionWidth, height: workspaceSidebarPagerHeight, alignment: .center)
        }
    }

    var projectDotTrack: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 6) {
                ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                    projectDot(
                        project,
                        index: index,
                        swipeProgress: dotSwipeProgress(for: index),
                        edgeProgress: dotEdgeProgress(for: index),
                    )
                }
            }
            .padding(.horizontal, isCompact ? 2 : 5)
            .frame(minWidth: projectTrackWidth, minHeight: workspaceSidebarPagerHeight, alignment: .center)
        }
        .frame(width: projectTrackWidth, height: workspaceSidebarPagerHeight, alignment: .center)
        .clipped()
    }

    @ViewBuilder
    var projectMenu: some View {
        if let selectedProject, editingProjectId == selectedProject.id {
            projectMenuInlineEditor(selectedProject)
        } else {
            WorkspaceSidebarProjectMenuButton(
                projects: projects,
                selectedProjectId: selectedProjectId,
                selectedProjectName: selectedProject?.displayName ?? "Project",
                width: projectMenuWidth,
                isHovered: isHovered,
                canDeleteSelectedProject: selectedProject.map { canDeleteWorkspaceProject($0.id) } ?? false,
                onSelectProject: { projectId in
                    selectWorkspaceSidebarProject(projectId)
                },
                onCreateProject: {
                    createWorkspaceSidebarProject()
                },
                onRenameSelectedProject: {
                    if let selectedProject {
                        beginInlineRename(selectedProject)
                    }
                },
                onSetSelectedProjectColor: { colorHex in
                    if let selectedProject {
                        setWorkspaceSidebarProjectColor(selectedProject, colorHex: colorHex)
                    }
                },
                onDeleteSelectedProject: {
                    if let selectedProject {
                        deleteWorkspaceSidebarProject(selectedProject)
                    }
                },
                onOpenDeckProfile: { profileName, destination in
                    launchDeckProfile(profileName, destination: destination)
                },
            )
            .frame(width: projectMenuWidth, height: workspaceSidebarPagerHeight, alignment: .leading)
            .contextMenu {
                if let selectedProject {
                    projectContextMenuItems(for: selectedProject)
                }
            }
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
                setWorkspaceSidebarProjectColor(project, colorHex: nil)
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
                    setWorkspaceSidebarProjectColor(project, colorHex: preset.hex)
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
            deleteWorkspaceSidebarProject(project)
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
