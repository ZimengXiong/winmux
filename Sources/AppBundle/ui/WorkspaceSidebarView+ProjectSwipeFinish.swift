import Common
import SwiftUI

extension WorkspaceSidebarView {
    func handleProjectSwipeEnded(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) {
        guard let direction = validProjectSwipeEndDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
            expansionProgress: expansionProgress,
        ) else {
            finishProjectSwipeSnapBack()
            return
        }
        if projectSwipeStartProjectId == nil,
           let selectedProjectIndex {
            projectSwipeStartProjectId = snapshot.projects[selectedProjectIndex].id
        }
        if finishProjectSwipeCreationIfNeeded(direction: direction, distance: abs(horizontalTranslation)) {
            return
        }
        finishProjectSwipeNavigationIfNeeded(direction: direction, distance: abs(horizontalTranslation))
    }

    func finishProjectSwipeSnapBack() {
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.9)) {
            resetProjectSwipe()
        }
    }

    private func finishProjectSwipeCreationIfNeeded(direction: Int, distance: CGFloat) -> Bool {
        guard shouldCreateWorkspaceSidebarProjectAfterSwipe(
            currentIndex: projectPagerDisplayIndex,
            projectCount: snapshot.projects.count,
            direction: direction,
            distance: distance,
        ) else {
            return false
        }
        performWorkspaceSidebarProjectHaptic(.levelChange)
        finishProjectSwipeCreation()
        return true
    }

    private func finishProjectSwipeNavigationIfNeeded(direction: Int, distance: CGFloat) {
        guard let nextIndex = workspaceSidebarProjectIndexAfterSwipe(
            currentIndex: projectPagerDisplayIndex,
            projectCount: snapshot.projects.count,
            direction: direction,
        ), distance >= workspaceSidebarProjectSwipeNavigateThreshold else {
            performWorkspaceSidebarProjectHaptic(.alignment)
            finishProjectSwipeSnapBack()
            return
        }
        finishProjectSwipeNavigation(to: snapshot.projects[nextIndex].id, direction: direction)
    }
}
