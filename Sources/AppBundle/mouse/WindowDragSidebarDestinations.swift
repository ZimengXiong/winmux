import AppKit
import Common

private let sidebarWorkspaceDropTargetHitSlop = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

private func sidebarWorkspaceDropInteractionRect(for target: WorkspaceSidebarDropTarget) -> Rect {
    target.rect.expanded(
        left: sidebarWorkspaceDropTargetHitSlop.left,
        right: sidebarWorkspaceDropTargetHitSlop.right,
        top: sidebarWorkspaceDropTargetHitSlop.top,
        bottom: sidebarWorkspaceDropTargetHitSlop.bottom,
    )
}

func isActionableSidebarWorkspaceDropTarget(
    sourceWorkspaceName: String?,
    targetKind: WorkspaceSidebarDropTargetKind?,
) -> Bool {
    switch targetKind {
        case .workspace(let workspaceName):
            return sourceWorkspaceName != workspaceName
        case .monitor:
            return true
        case .newWorkspace:
            return true
        case nil:
            return false
    }
}

@MainActor
func currentSidebarWorkspaceDropDestination(sourceWindow: Window, mouseLocation: CGPoint, subject: WindowDragSubject) -> WindowDragIntentDestination? {
    let sourceLabel = sidebarDragSourceTitle(for: sourceWindow, subject: subject)
    let isGroup = subject == .group
    let sourceWorkspaceName = dragSubjectNode(for: sourceWindow, subject: subject).nodeWorkspace?.name
    if let target = workspaceSidebarDropTarget(at: mouseLocation, hitSlop: sidebarWorkspaceDropTargetHitSlop),
       isActionableSidebarWorkspaceDropTarget(sourceWorkspaceName: sourceWorkspaceName, targetKind: target.kind)
    {
        switch target.kind {
            case .monitor(let scopeId):
                guard let monitor = workspaceSidebarMonitor(forScopeId: scopeId) else { return nil }
                let workspace = monitor.activeWorkspace
                guard workspace.name != sourceWorkspaceName else { return nil }
                return WindowDragIntentDestination(
                    kind: .moveToWorkspace(workspaceName: workspace.name),
                    previewContainerRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                    previewRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                    interactionRect: sidebarWorkspaceDropInteractionRect(for: target),
                    title: sourceLabel,
                    subtitle: "Drop to send this item to \(workspaceSidebarMonitorDisplayName(monitor))",
                    previewStyle: .sidebarWorkspaceMove,
                    previewGeometry: .rounded,
                    isGroup: isGroup,
                )
            case .workspace(let workspaceName):
                return WindowDragIntentDestination(
                    kind: .moveToWorkspace(workspaceName: workspaceName),
                    previewContainerRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                    previewRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                    interactionRect: sidebarWorkspaceDropInteractionRect(for: target),
                    title: sourceLabel,
                    subtitle: "Drop to send this item to \(workspaceName)",
                    previewStyle: .sidebarWorkspaceMove,
                    previewGeometry: .rounded,
                    isGroup: isGroup,
                )
            case .newWorkspace(let projectId, let monitorScopeId):
                return WindowDragIntentDestination(
                    kind: .createWorkspace(projectId: projectId, monitorScopeId: monitorScopeId),
                    previewContainerRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                    previewRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                    interactionRect: sidebarWorkspaceDropInteractionRect(for: target),
                    title: sourceLabel,
                    subtitle: "Drop to create a workspace and move this item there",
                    previewStyle: .sidebarWorkspaceMove,
                    previewGeometry: .rounded,
                    isGroup: isGroup,
                )
        }
    }
    return nil
}

@MainActor
func workspaceSidebarMonitorDisplayName(_ monitor: Monitor) -> String {
    let name = monitor.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if monitor.isMain {
        return "Main Display"
    }
    return name.isEmpty ? "Display \(monitor.monitorId_oneBased ?? 0)" : name
}

@MainActor
func currentTabDetachDestination(sourceWindow: Window, mouseLocation: CGPoint, origin: TabDetachOrigin) -> WindowDragIntentDestination? {
    guard let parent = sourceWindow.parent as? TilingContainer,
          parent.layout == .tabGroup,
          parent.children.count > 1,
          let keepRect = sourceWindow.tabDetachKeepRect(origin: origin),
          !keepRect.contains(mouseLocation),
          let previewRect = sourceWindow.tabDetachPreviewRect
    else { return nil }

    return WindowDragIntentDestination(
        kind: .detachTab(windowId: sourceWindow.windowId),
        previewContainerRect: sourceWindow.windowDragVisibleRect ?? previewRect,
        previewRect: previewRect,
        interactionRect: previewRect.expanded(left: 18, right: 18, top: 10, bottom: 18),
        title: "Detach Tab",
        subtitle: "Release to pull this window out of the stack",
        previewStyle: .detach,
        previewGeometry: .rounded,
        isGroup: false,
    )
}

@MainActor
func shouldSuppressSameTabGroupTabDestination(sourceWindow: Window, targetWindow: Window, detachOrigin _: TabDetachOrigin) -> Bool {
    guard let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .tabGroup,
          targetWindow.parent === sourceParent
    else { return false }
    return true
}

@MainActor
func shouldSuppressSameTabGroupSwapDestination(
    sourceWindow: Window,
    targetWindow: Window,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> Bool {
    guard subject == .window,
          detachOrigin == .tabStrip,
          let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .tabGroup,
          targetWindow.parent === sourceParent
    else { return false }
    return true
}
