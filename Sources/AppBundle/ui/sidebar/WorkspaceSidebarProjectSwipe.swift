import SwiftUI

func workspaceSidebarProjectSwipeDirection(
    horizontalTranslation: CGFloat,
    verticalTranslation: CGFloat,
    minimumDistance: CGFloat = workspaceSidebarProjectSwipeIntentThreshold,
) -> Int? {
    let horizontalDistance = abs(horizontalTranslation)
    guard horizontalDistance >= minimumDistance,
          horizontalDistance > abs(verticalTranslation) * 1.8
    else { return nil }
    return horizontalTranslation < 0 ? 1 : -1
}

func workspaceSidebarProjectIndexAfterSwipe(currentIndex: Int?, projectCount: Int, direction: Int) -> Int? {
    guard let currentIndex, projectCount > 0, (0 ..< projectCount).contains(currentIndex) else { return nil }
    let nextIndex = currentIndex + direction
    return (0 ..< projectCount).contains(nextIndex) ? nextIndex : nil
}

func shouldRenderWorkspaceSidebarProjectPage(index: Int, displayIndex: Int, swipeDirection: Int?, projectCount: Int) -> Bool {
    guard index != displayIndex else { return true }
    guard let swipeDirection else { return false }
    return index == workspaceSidebarProjectIndexAfterSwipe(
        currentIndex: displayIndex,
        projectCount: projectCount,
        direction: swipeDirection,
    )
}
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
func workspaceSidebarProjectResistedOffset(
    horizontalTranslation: CGFloat,
    currentIndex: Int?,
    projectCount: Int,
) -> CGFloat {
    let direction = horizontalTranslation < 0 ? 1 : -1
    let isPastProjectEdge = workspaceSidebarProjectIndexAfterSwipe(
        currentIndex: currentIndex,
        projectCount: projectCount,
        direction: direction,
    ) == nil
    let divisor: CGFloat = isPastProjectEdge ? 2.2 : 1.0
    let limit: CGFloat = isPastProjectEdge ? 52 : 72
    return max(-limit, min(limit, horizontalTranslation / divisor))
}

func workspaceSidebarProjectPagerDragOffset(
    horizontalTranslation: CGFloat,
    currentIndex: Int?,
    projectCount: Int,
    pageWidth: CGFloat,
) -> CGFloat {
    guard pageWidth > 0,
          let direction = workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: 0,
            minimumDistance: 1,
          )
    else { return 0 }
    guard workspaceSidebarProjectIndexAfterSwipe(
        currentIndex: currentIndex,
        projectCount: projectCount,
        direction: direction,
    ) != nil else {
        return workspaceSidebarProjectResistedOffset(
            horizontalTranslation: horizontalTranslation,
            currentIndex: currentIndex,
            projectCount: projectCount,
        )
    }
    return max(-pageWidth, min(pageWidth, horizontalTranslation))
}
func workspaceSidebarProjectSwipeSwitchProgress(distance: CGFloat) -> CGFloat {
    min(max(distance / workspaceSidebarProjectSwipeNavigateThreshold, 0), 1)
}

func workspaceSidebarProjectSwipeTranslationAfterScroll(currentTranslation: CGFloat, scrollingDeltaX: CGFloat) -> CGFloat {
    currentTranslation - scrollingDeltaX
}
