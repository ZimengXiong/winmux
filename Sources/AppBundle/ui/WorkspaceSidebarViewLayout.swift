import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarView {
    func sidebarContent(expansionProgress: CGFloat) -> some View {
        let isCompact = expansionProgress < workspaceSidebarRowsRevealProgress
        let leadingInset = workspaceSidebarOuterLeadingPadding(isCompact: isCompact)
        let trailingInset = workspaceSidebarOuterTrailingPadding(isCompact: isCompact)
        let showsMonitorSelector = !isCompact && snapshot.configuration.showMonitorSelector
        let projectSwipeDirection = workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: projectSwipeTranslation,
            verticalTranslation: 0,
            minimumDistance: 1,
        )
        let activeProjectIndex = projectPagerDisplayIndex
        let projectSwipeProgress = workspaceSidebarProjectEdgeCreationProgress(
            currentIndex: activeProjectIndex,
            projectCount: snapshot.projects.count,
            direction: projectSwipeDirection,
            distance: abs(projectSwipeTranslation),
        )
        let hasSwipeTarget = projectSwipeDirection.flatMap { direction in
            workspaceSidebarProjectIndexAfterSwipe(
                currentIndex: activeProjectIndex,
                projectCount: snapshot.projects.count,
                direction: direction,
            )
        } != nil
        let projectSwitchProgress = hasSwipeTarget
            ? workspaceSidebarProjectSwipeSwitchProgress(distance: abs(projectSwipeTranslation))
            : 0
        let visibleWorkspacesByProject = workspaceSidebarVisibleWorkspacesByProject(
            workspaces: snapshot.workspaces,
            selectedScopeId: snapshot.selectedMonitorScopeId,
            focusedMonitorScopeId: snapshot.focusedMonitorScopeId,
        )

        return VStack(alignment: .leading, spacing: 0) {
            if showsMonitorSelector {
                monitorSelectorSection(
                    expansionProgress: expansionProgress,
                    leadingInset: leadingInset,
                    trailingInset: trailingInset,
                )
            }

            projectPagerContent(
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: showsMonitorSelector ? 0 : snapshot.configuration.topPadding,
                visibleWorkspacesByProject: visibleWorkspacesByProject,
                swipeDirection: projectSwipeDirection,
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            projectPagerSection(
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                swipeDirection: projectSwipeDirection,
                switchProgress: projectSwitchProgress,
                edgeProgress: projectSwipeProgress,
            )

            statusSection(
                expansionProgress: expansionProgress,
                isCompact: isCompact,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
            )
        }
        .coordinateSpace(name: "workspaceSidebarContent")
        .onPreferenceChange(WorkspaceSidebarDropTargetPreferenceKey.self) { frames in
            actions.setDropTargets(frames)
        }
        .background {
            sidebarSurface(in: sidebarShape)
        }
        .environment(\.colorScheme, .dark)
        .clipShape(sidebarShape)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(mattePanelSeparator.opacity(0.72))
                .frame(width: 0.5)
        }
        .shadow(
            color: Color.black.opacity(0.28),
            radius: 14,
            x: 2,
            y: 0
        )
        .overlay {
            sidebarSwipeCaptureOverlay(expansionProgress: expansionProgress)
        }
        .simultaneousGesture(projectSwipeGesture(expansionProgress: expansionProgress))
    }
}
