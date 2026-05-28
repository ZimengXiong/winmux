import Common
import SwiftUI

extension WorkspaceSidebarView {
    func projectPagerSection(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        swipeDirection: Int?,
        switchProgress: CGFloat,
        edgeProgress: CGFloat,
    ) -> some View {
        WorkspaceSidebarProjectPager(
            projects: snapshot.projects,
            selectedProjectId: snapshot.activeProjectId,
            expansionProgress: expansionProgress,
            layout: snapshot.configuration,
            isProjectMenuOpen: $isProjectMenuOpen,
            renamingProjectId: $renamingProjectId,
            renamingProjectText: $renamingProjectText,
            onSelectProject: { projectId in
                debugWorkspaceSidebarProjectLog(
                    "pagerSectionSelect project=\(projectId.rawValue) active=\(snapshot.activeProjectId.rawValue) browsed=\(browsedProjectId?.rawValue ?? "nil")"
                )
                browseMode = .activeProject
                actions.send(.selectProject(projectId))
            },
            onCreateProject: { actions.send(.createProject) },
            onBeginRenameProject: { project in
                beginProjectRename(project)
            },
            onCommitRenameProject: {
                finishProjectRename()
            },
            onCancelRenameProject: {
                finishProjectRename(cancelled: true)
            },
            onSetProjectColor: { project, colorHex in
                actions.send(.setProjectColor(project.id, colorHex: colorHex))
            },
            onDeleteProject: { project in
                actions.send(.deleteProject(project.id))
            },
        )
        .zIndex(2)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
