import Common
import SwiftUI

extension WorkspaceSidebarView {
    @ViewBuilder
    func projectPagerContent(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        visibleWorkspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
        swipeDirection: Int?,
    ) -> some View {
        if let browsedProjectId,
           browsedProjectId != snapshot.activeProjectId
        {
            splitWorkspacePage(
                activeProjectId: snapshot.activeProjectId,
                browsedProjectId: browsedProjectId,
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                visibleWorkspacesByProject: visibleWorkspacesByProject
            )
        } else if snapshot.projects.isEmpty {
            workspacePage(
                projectId: snapshot.activeProjectId,
                workspaces: visibleWorkspacesByProject[snapshot.activeProjectId] ?? [],
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                isInteractive: true,
                showsPinnedActiveWorkspace: true,
                showsCreateWorkspace: true,
                allowsActivation: allowsWorkspaceActivation(projectId: snapshot.activeProjectId),
            )
        } else {
            projectPagerPages(
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                visibleWorkspacesByProject: visibleWorkspacesByProject,
                swipeDirection: swipeDirection,
            )
        }
    }

    func projectPagerPages(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        visibleWorkspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
        swipeDirection: Int?,
    ) -> some View {
        GeometryReader { geometry in
            let pageWidth = max(geometry.size.width, 1)
            let displayIndex = projectPagerDisplayIndex ?? 0
            let dragOffset = workspaceSidebarProjectPagerDragOffset(
                horizontalTranslation: projectSwipeTranslation,
                currentIndex: displayIndex,
                projectCount: snapshot.projects.count,
                pageWidth: pageWidth,
            )

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(snapshot.projects.enumerated()), id: \.element.id) { index, project in
                    projectPageSlot(
                        index: index,
                        project: project,
                        displayIndex: displayIndex,
                        pageWidth: pageWidth,
                        expansionProgress: expansionProgress,
                        leadingInset: leadingInset,
                        trailingInset: trailingInset,
                        topPadding: topPadding,
                        visibleWorkspacesByProject: visibleWorkspacesByProject,
                        swipeDirection: swipeDirection,
                    )
                }
            }
            .offset(x: -CGFloat(displayIndex) * pageWidth + dragOffset)
            .onAppear { projectPagerWidth = pageWidth }
            .onChange(of: pageWidth) { projectPagerWidth = $0 }
        }
        .clipped()
    }
}
