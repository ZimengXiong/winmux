import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarView {
    var selectedProjectIndex: Int? {
        viewModel.workspaceSidebarProjects.firstIndex { $0.id == viewModel.workspaceSidebarSelectedProjectId }
            ?? viewModel.workspaceSidebarProjects.indices.first
    }

    var projectPagerDisplayIndex: Int? {
        if let projectSwipeStartProjectId,
           let index = viewModel.workspaceSidebarProjects.firstIndex(where: { $0.id == projectSwipeStartProjectId }) {
            return index
        }
        return selectedProjectIndex
    }

    func projectSwipeGesture(expansionProgress: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                handleProjectSwipeChanged(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height,
                    expansionProgress: expansionProgress,
                )
            }
            .onEnded { value in
                handleProjectSwipeEnded(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height,
                    expansionProgress: expansionProgress,
                )
            }
    }

    func handleProjectSwipeChanged(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) {
        guard shouldHandleProjectSwipe(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
            expansionProgress: expansionProgress,
        ) else {
            resetProjectSwipe()
            return
        }
        if projectSwipeStartProjectId == nil,
           let selectedProjectIndex {
            projectSwipeStartProjectId = viewModel.workspaceSidebarProjects[selectedProjectIndex].id
        }
        projectSwipeTranslation = horizontalTranslation
        guard let direction = workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
        ) else {
            return
        }
        let activeProjectIndex = projectPagerDisplayIndex
        let shouldCreate = shouldCreateWorkspaceSidebarProjectAfterSwipe(
            currentIndex: activeProjectIndex,
            projectCount: viewModel.workspaceSidebarProjects.count,
            direction: direction,
            distance: abs(horizontalTranslation),
        )
        let shouldNavigate =
            workspaceSidebarProjectIndexAfterSwipe(
                currentIndex: activeProjectIndex,
                projectCount: viewModel.workspaceSidebarProjects.count,
                direction: direction,
            ) != nil &&
            abs(horizontalTranslation) >= workspaceSidebarProjectSwipeNavigateThreshold
        let shouldCommit = shouldCreate || shouldNavigate
        if shouldCommit && !projectSwipeDidCrossBreakPoint {
            projectSwipeDidCrossBreakPoint = true
            performWorkspaceSidebarProjectHaptic(.alignment)
        } else if !shouldCommit {
            projectSwipeDidCrossBreakPoint = false
        }
    }

    func handleProjectSwipeEnded(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) {
        guard shouldHandleProjectSwipe(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
            expansionProgress: expansionProgress,
        ),
              let direction = workspaceSidebarProjectSwipeDirection(
                horizontalTranslation: horizontalTranslation,
                verticalTranslation: verticalTranslation,
              )
        else {
            finishProjectSwipeSnapBack()
            return
        }
        if projectSwipeStartProjectId == nil,
           let selectedProjectIndex {
            projectSwipeStartProjectId = viewModel.workspaceSidebarProjects[selectedProjectIndex].id
        }
        let activeProjectIndex = projectPagerDisplayIndex
        if shouldCreateWorkspaceSidebarProjectAfterSwipe(
            currentIndex: activeProjectIndex,
            projectCount: viewModel.workspaceSidebarProjects.count,
            direction: direction,
            distance: abs(horizontalTranslation),
        ) {
            performWorkspaceSidebarProjectHaptic(.levelChange)
            finishProjectSwipeCreation()
            return
        }
        guard let nextIndex = workspaceSidebarProjectIndexAfterSwipe(
            currentIndex: activeProjectIndex,
            projectCount: viewModel.workspaceSidebarProjects.count,
            direction: direction,
        ), abs(horizontalTranslation) >= workspaceSidebarProjectSwipeNavigateThreshold else {
            performWorkspaceSidebarProjectHaptic(.alignment)
            finishProjectSwipeSnapBack()
            return
        }
        finishProjectSwipeNavigation(
            to: viewModel.workspaceSidebarProjects[nextIndex].id,
            direction: direction,
        )
    }

    func shouldHandleProjectSwipe(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) -> Bool {
        guard !viewModel.workspaceSidebarProjects.isEmpty,
              !isWorkspaceSidebarDragInProgress()
        else {
            return false
        }
        return workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
        ) != nil
    }

    func resetProjectSwipe() {
        projectSwipeTranslation = 0
        projectSwipeStartProjectId = nil
        projectSwipeDidCrossBreakPoint = false
    }

    func resetProjectSwipeWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            resetProjectSwipe()
        }
    }

    func finishProjectSwipeSnapBack() {
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.9)) {
            resetProjectSwipe()
        }
    }

    func finishProjectSwipeNavigation(to projectId: WorkspaceProjectId, direction: Int) {
        let startProjectId = projectSwipeStartProjectId
        let fullPageOffset = -CGFloat(direction) * max(projectPagerWidth, CGFloat(config.workspaceSidebar.width), 1)
        withAnimation(.easeOut(duration: 0.12)) {
            projectSwipeTranslation = fullPageOffset
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard projectSwipeStartProjectId == startProjectId else { return }
            selectWorkspaceSidebarProject(projectId)
            resetProjectSwipeWithoutAnimation()
        }
    }

    func finishProjectSwipeCreation() {
        withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.9)) {
            resetProjectSwipe()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard projectSwipeStartProjectId == nil else { return }
            createWorkspaceSidebarProject()
        }
    }

    func performWorkspaceSidebarProjectHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
