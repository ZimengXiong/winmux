import SwiftUI

func workspaceSidebarProjectSwipeSwitchProgress(distance: CGFloat) -> CGFloat {
    min(max(distance / workspaceSidebarProjectSwipeNavigateThreshold, 0), 1)
}

func workspaceSidebarProjectSwipeTranslationAfterScroll(currentTranslation: CGFloat, scrollingDeltaX: CGFloat) -> CGFloat {
    currentTranslation - scrollingDeltaX
}
