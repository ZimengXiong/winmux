import SwiftUI

func workspaceSidebarOuterLeadingPadding(isCompact: Bool) -> CGFloat {
    isCompact ? workspaceSidebarCompactRailHorizontalInset : workspaceSidebarContentLeadingInset
}

func workspaceSidebarOuterTrailingPadding(isCompact: Bool) -> CGFloat {
    isCompact ? workspaceSidebarCompactRailHorizontalInset : workspaceSidebarContentTrailingInset
}

func workspaceSidebarStatusBottomPadding(isCompact: Bool) -> CGFloat {
    workspaceSidebarOuterLeadingPadding(isCompact: isCompact)
}

func workspaceSidebarHoverCueWidth(collapsedWidth: CGFloat, expandedWidth: CGFloat) -> CGFloat {
    min(collapsedWidth, expandedWidth)
}
