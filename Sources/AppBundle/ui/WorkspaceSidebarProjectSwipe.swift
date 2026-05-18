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
