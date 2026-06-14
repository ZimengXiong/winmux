import Foundation

func nextWorkspaceSidebarHoveredWorkspaceName(
    currentHoveredWorkspaceName: String?,
    workspaceName: String,
    isHovering: Bool,
) -> String? {
    if isHovering { return workspaceName }
    return currentHoveredWorkspaceName == workspaceName ? nil : currentHoveredWorkspaceName
}

func nextWorkspaceSidebarHoveredWindowId(
    currentHoveredWindowId: UInt32?,
    windowId: UInt32,
    isHovering: Bool,
) -> UInt32? {
    if isHovering { return windowId }
    return currentHoveredWindowId == windowId ? nil : currentHoveredWindowId
}
