import SwiftUI

@MainActor
func workspaceSidebarCompactSectionWidth(layout: WorkspaceSidebarLayoutSnapshot) -> CGFloat {
    max(
        layout.collapsedWidth - (workspaceSidebarCompactRailHorizontalInset * 2),
        workspaceSidebarBadgeWidth + (workspaceSidebarSectionInnerHorizontalInset * 2),
    )
}

@MainActor
func workspaceSidebarExpandedSectionWidth(layout: WorkspaceSidebarLayoutSnapshot) -> CGFloat {
    max(
        layout.expandedWidth -
            workspaceSidebarContentLeadingInset -
            workspaceSidebarContentTrailingInset,
        workspaceSidebarCompactSectionWidth(layout: layout),
    )
}

@MainActor
func workspaceSidebarSectionWidth(_ expansionProgress: CGFloat, layout: WorkspaceSidebarLayoutSnapshot) -> CGFloat {
    let compact = workspaceSidebarCompactSectionWidth(layout: layout)
    let expanded = workspaceSidebarExpandedSectionWidth(layout: layout)
    return compact + (expanded - compact) * expansionProgress
}

@MainActor
func workspaceSidebarContentWidth(_ expansionProgress: CGFloat, layout: WorkspaceSidebarLayoutSnapshot) -> CGFloat {
    max(
        workspaceSidebarSectionWidth(expansionProgress, layout: layout) -
            (workspaceSidebarSectionInnerHorizontalInset * 2) -
            workspaceSidebarBadgeWidth -
            workspaceSidebarHeaderSpacing,
        0,
    )
}
