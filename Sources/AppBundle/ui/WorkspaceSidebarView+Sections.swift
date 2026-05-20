import Common
import SwiftUI

extension WorkspaceSidebarView {
    func monitorSelectorSection(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
    ) -> some View {
        WorkspaceSidebarMonitorSelector(
            scopes: snapshot.monitorScopes,
            projects: snapshot.projects,
            selectedScopeId: snapshot.selectedMonitorScopeId,
            activeProjectId: snapshot.selectedProjectId,
            browsedProjectId: browsedProjectId,
            expansionProgress: expansionProgress,
            sectionWidth: workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration),
            onSelectScope: { scopeId in
                if scopeId == workspaceSidebarDefaultScopeId {
                    browsedProjectId = nil
                }
                actions.send(.selectMonitorScope(scopeId))
            },
            onSelectProject: { projectId in
                browsedProjectId = projectId == snapshot.selectedProjectId ? nil : projectId
            },
            onCreateProject: {
                actions.send(.createProject)
            },
            onRenameProject: { project in
                beginProjectRename(project)
            },
            renamingProjectId: $renamingProjectId,
            renamingProjectText: $renamingProjectText,
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
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, snapshot.configuration.topPadding)
        .padding(.bottom, workspaceSidebarSectionGap)
        .zIndex(100)
    }

    func statusSection(
        expansionProgress: CGFloat,
        isCompact: Bool,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
    ) -> some View {
        WorkspaceSidebarStatusView(
            sectionWidth: workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration),
            isCompact: isCompact,
            showsDate: snapshot.configuration.showsDate,
            showsStatusPills: snapshot.configuration.showsStatusPills,
        )
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, 4)
        .padding(.bottom, workspaceSidebarStatusBottomPadding(isCompact: isCompact) + 4)
    }
}
