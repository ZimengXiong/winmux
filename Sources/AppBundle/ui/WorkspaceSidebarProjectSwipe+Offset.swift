import SwiftUI

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
