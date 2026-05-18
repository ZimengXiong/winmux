import SwiftUI

func shouldCreateWorkspaceSidebarProjectAfterSwipe(
    currentIndex: Int?,
    projectCount: Int,
    direction: Int,
    distance: CGFloat,
) -> Bool {
    guard let currentIndex, projectCount > 0 else { return false }
    let pulledBeforeFirst = direction < 0 && currentIndex == 0
    let pulledAfterLast = direction > 0 && currentIndex == projectCount - 1
    return (pulledBeforeFirst || pulledAfterLast) && distance >= workspaceSidebarProjectSwipeCreateThreshold
}

func workspaceSidebarProjectEdgeCreationProgress(
    currentIndex: Int?,
    projectCount: Int,
    direction: Int?,
    distance: CGFloat,
) -> CGFloat {
    guard let currentIndex, let direction, projectCount > 0 else { return 0 }
    let pulledBeforeFirst = direction < 0 && currentIndex == 0
    let pulledAfterLast = direction > 0 && currentIndex == projectCount - 1
    guard pulledBeforeFirst || pulledAfterLast else { return 0 }
    let range = max(workspaceSidebarProjectSwipeCreateThreshold - workspaceSidebarProjectSwipeFormationStart, 1)
    return min(max((distance - workspaceSidebarProjectSwipeFormationStart) / range, 0), 1)
}
