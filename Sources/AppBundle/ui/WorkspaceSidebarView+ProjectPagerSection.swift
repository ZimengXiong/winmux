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
            selectedProjectId: snapshot.selectedProjectId,
            expansionProgress: expansionProgress,
            layout: snapshot.layout,
            isProjectMenuOpen: $isProjectMenuOpen,
            onSelectProject: { actions.send(.selectProject($0)) },
            onCreateProject: { actions.send(.createProject) },
            onRenameProject: { project, displayName in
                actions.send(.renameProject(project.id, displayName: displayName))
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
