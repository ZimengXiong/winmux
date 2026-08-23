import AppKit

func workspaceSidebarAllowsLeftEdgeTrap(_ sidebarConfig: WorkspaceSidebarConfig) -> Bool {
    !sidebarConfig.alwaysExpanded
}

func workspaceSidebarRestingWidth(_ sidebarConfig: WorkspaceSidebarConfig) -> CGFloat {
    if sidebarConfig.alwaysExpanded {
        return CGFloat(sidebarConfig.width)
    }
    return sidebarConfig.autoHide ? 0 : CGFloat(sidebarConfig.collapsedWidth)
}

func workspaceSidebarHoverActivationWidth(_ sidebarConfig: WorkspaceSidebarConfig) -> CGFloat {
    sidebarConfig.alwaysExpanded ? CGFloat(sidebarConfig.width) : CGFloat(sidebarConfig.collapsedWidth)
}

func workspaceSidebarCollapsedContentWidth(_ sidebarConfig: WorkspaceSidebarConfig) -> CGFloat {
    sidebarConfig.autoHide && !sidebarConfig.alwaysExpanded ? 0 : CGFloat(sidebarConfig.collapsedWidth)
}

func workspaceSidebarPersistentVisibleWidth(
    currentWidth: CGFloat,
    previousExpandedWidth: CGFloat?,
    expandedWidth: CGFloat,
) -> CGFloat {
    let wasShowingSplitBrowse = previousExpandedWidth.map { currentWidth > $0 + 0.5 } ?? false
    return wasShowingSplitBrowse ? expandedWidth * 2 : expandedWidth
}

func isWorkspaceSidebarHoverDeepEnoughToExpand(
    mouseX: CGFloat,
    sidebarMinX: CGFloat,
    collapsedWidth: CGFloat,
) -> Bool {
    guard collapsedWidth > 0 else { return false }
    let sidebarMaxX = sidebarMinX + collapsedWidth
    return sidebarMaxX - mouseX >= collapsedWidth * workspaceSidebarHoverOpenThresholdFraction
}

func shouldDelayWorkspaceSidebarExpansion(
    isExpanded: Bool,
    isExpansionLocked: Bool,
    isMouseWindowDragInProgress: Bool,
) -> Bool {
    !isExpanded && !isExpansionLocked && !isMouseWindowDragInProgress
}

func shouldSuppressWorkspaceSidebarHoverExpansionForDrag(
    isSidebarItemDragActive: Bool,
    isSidebarOriginatedDrag: Bool,
) -> Bool {
    isSidebarItemDragActive || isSidebarOriginatedDrag
}
