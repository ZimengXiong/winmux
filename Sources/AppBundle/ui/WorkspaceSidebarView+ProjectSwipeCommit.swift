import Common
import SwiftUI

extension WorkspaceSidebarView {
    func validProjectSwipeEndDirection(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) -> Int? {
        guard shouldHandleProjectSwipe(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
            expansionProgress: expansionProgress,
        ) else {
            return nil
        }
        return workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
        )
    }

    func finishProjectSwipeNavigation(to projectId: WorkspaceProjectId, direction: Int) {
        let startProjectId = projectSwipeStartProjectId
        let fullPageOffset = -CGFloat(direction) * max(projectPagerWidth, snapshot.configuration.expandedWidth, 1)
        withAnimation(.easeOut(duration: 0.12)) {
            projectSwipeTranslation = fullPageOffset
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard projectSwipeStartProjectId == startProjectId else { return }
            actions.send(.selectProject(projectId))
            resetProjectSwipeWithoutAnimation()
        }
    }

    func finishProjectSwipeCreation() {
        withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.9)) {
            resetProjectSwipe()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard projectSwipeStartProjectId == nil else { return }
            actions.send(.createProject)
        }
    }
}
