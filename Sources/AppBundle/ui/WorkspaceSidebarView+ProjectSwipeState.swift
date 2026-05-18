import AppKit
import SwiftUI

extension WorkspaceSidebarView {
    var selectedProjectIndex: Int? {
        let projectId = browsedProjectId ?? snapshot.selectedProjectId
        return snapshot.projects.firstIndex { $0.id == projectId }
            ?? snapshot.projects.indices.first
    }

    var projectPagerDisplayIndex: Int? {
        if let projectSwipeStartProjectId,
           let index = snapshot.projects.firstIndex(where: { $0.id == projectSwipeStartProjectId }) {
            return index
        }
        return selectedProjectIndex
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

    func performWorkspaceSidebarProjectHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
