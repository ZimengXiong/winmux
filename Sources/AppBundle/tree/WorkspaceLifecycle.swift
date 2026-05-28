import AppKit
import Common

@MainActor
func switchWorkspaceProject(_ projectId: WorkspaceProjectId, on monitor: Monitor) -> Workspace? {
    materializePersistedWorkspaceProjects()
    guard winMuxWorkspaceState.projectsById[projectId] != nil else {
        debugWorkspaceSidebarProjectLog("switchProjectAbort unknownProject=\(projectId.rawValue)")
        return nil
    }
    let viewportId = MonitorViewportId(monitor)
    let rememberedWorkspace = winMuxWorkspaceState.monitorViewportsById[viewportId]?
        .lastActiveWorkspaceByProject[projectId]
        .flatMap { winMuxWorkspaceState.workspaceById[$0] }
        .flatMap { workspaceIsAvailableForMonitor($0, monitor: monitor) ? $0 : nil }
    let workspace = rememberedWorkspace
        ?? availablePreferredWorkspace(projectId: projectId, monitor: monitor)
        ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
    let didSetActive = monitor.setActiveWorkspace(workspace)
    debugWorkspaceSidebarProjectLog(
        "switchProject project=\(projectId.rawValue) viewport=\(viewportId.description) remembered=\(rememberedWorkspace?.name ?? "nil") chosen=\(workspace.name) chosenProject=\(workspace.projectId.rawValue) didSetActive=\(didSetActive)"
    )
    return didSetActive ? workspace : nil
}

@MainActor
func preferredWorkspace(projectId: WorkspaceProjectId, monitor: Monitor) -> Workspace? {
    projectWorkspaces(projectId: projectId)
        .filter { !$0.isArchived }
        .filter { isValidAssignment(workspace: $0, screen: monitor.rect.topLeftCorner) }
        .first
}

@MainActor
func createBlankWorkspace(projectId: WorkspaceProjectId, monitor: Monitor) -> Workspace {
    let workspace = Workspace.get(byName: nextAutomaticWorkspaceName(projectId: projectId, monitor: monitor))
    workspace.markAsTransientBlank()
    workspace.assignProject(projectId)
    workspace.seedMonitorIfNeeded(monitor)
    return workspace
}

@MainActor
func getOrCreateAdjacentBlankWorkspace(projectId: WorkspaceProjectId, monitor: Monitor) -> Workspace {
    let scope = WorkspaceScope(projectId: projectId)
    if let workspaceId = retainedEmptyWorkspaceId(in: scope),
       let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
       isValidAssignment(workspace: workspace, screen: monitor.rect.topLeftCorner)
    {
        return workspace
    }
    return createBlankWorkspace(projectId: projectId, monitor: monitor)
}

@MainActor
func deleteWorkspace(_ workspace: Workspace) throws {
    let fallback = workspaceFallbackForDeletion(
        excluding: workspace,
        projectId: workspace.projectId,
        monitor: workspace.workspaceMonitor,
    )
    moveWorkspaceContents(from: workspace, to: fallback)
    if workspace.isVisible {
        check(
            workspace.workspaceMonitor.setActiveWorkspace(fallback),
            "Can't activate fallback workspace '\(fallback.name)' while deleting workspace '\(workspace.name)'",
        )
    }
    if focus.workspace == workspace {
        _ = setFocus(to: fallback.toLiveFocus())
    }
    removeWorkspaceFromRegistry(workspace)
    checkWorkspaceHierarchyInvariants()
}

@MainActor
func workspaceFallbackForDeletion(
    excluding workspace: Workspace,
    projectId: WorkspaceProjectId,
    monitor: Monitor,
) -> Workspace {
    closestWorkspaceForDeletion(
        excluding: workspace,
        projectId: projectId,
        monitor: monitor,
    )
        ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
}

@MainActor
func closestWorkspaceForDeletion(
    excluding workspace: Workspace,
    projectId: WorkspaceProjectId,
    monitor: Monitor,
) -> Workspace? {
    let scopedCandidates = userFacingWorkspaces(
        orderedWorkspaces(in: projectId),
        focusedWorkspace: focus.workspace,
    )
        .filter { isValidAssignment(workspace: $0, screen: monitor.rect.topLeftCorner) }
    let automaticCandidates = scopedCandidates.filter(\.usesAutomaticDisplayName)
    let candidates = workspace.usesAutomaticDisplayName && automaticCandidates.contains(workspace)
        ? automaticCandidates
        : scopedCandidates

    guard let deletedIndex = candidates.firstIndex(where: { $0 === workspace }) else {
        return candidates.first { $0 !== workspace }
    }
    if let next = candidates.getOrNil(atIndex: deletedIndex + 1) {
        return next
    }
    if deletedIndex > 0 {
        return candidates[deletedIndex - 1]
    }
    return nil
}

@MainActor
func moveWorkspaceContents(from source: Workspace, to target: Workspace) {
    guard source != target else { return }
    for child in source.children {
        switch child.nodeCases {
            case .window(let window):
                window.bind(to: target, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            case .tilingContainer(let container):
                container.bind(to: target.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            case .macosFullscreenWindowsContainer(let container):
                for window in container.children.filterIsInstance(of: Window.self) {
                    window.bind(to: target.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                }
            case .macosHiddenAppsWindowsContainer(let container):
                for window in container.children.filterIsInstance(of: Window.self) {
                    window.bind(to: target.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                }
            case .workspace, .macosMinimizedWindowsContainer, .macosPopupWindowsContainer:
                break
        }
    }
    for window in workspaceOwnedMinimizedWindows(source) {
        switch window.layoutReason {
            case .macos(let prevParentKind, _):
                window.layoutReason = .macos(prevParentKind: prevParentKind, prevWorkspaceName: target.name)
            case .standard:
                break
        }
    }
}

@MainActor
func removeWorkspaceFromRegistry(_ workspace: Workspace) {
    clearWorkspaceSidebarLabelIfNeeded(workspace.name)
    _ = winMuxWorkspaceState.removeWorkspace(workspace)
}

@MainActor
func pruneEmptyWorkspaces() {
    let retainedEmptyWorkspaceIds = retainedEmptyWorkspaceIdsByScope()
    let focusedWorkspaceBeforePrune = focus.workspace
    let workspacesToRemove = Workspace.all.filter {
        !workspaceShouldSurviveReconciliation($0, retainedEmptyWorkspaceIds: retainedEmptyWorkspaceIds)
    }
    var focusedReplacement: Workspace?

    for workspace in workspacesToRemove {
        let replacement = replacementWorkspaceForPrunedWorkspace(
            workspace,
            retainedEmptyWorkspaceIds: retainedEmptyWorkspaceIds,
        )
        if workspace.isVisible, let replacement {
            check(
                workspace.workspaceMonitor.setActiveWorkspace(replacement),
                "Can't replace pruned empty workspace '\(workspace.name)' with '\(replacement.name)'",
            )
        }
        if workspace == focusedWorkspaceBeforePrune {
            focusedReplacement = focusReplacementForPrunedWorkspace(workspace) ?? replacement
        }
        removeWorkspaceFromRegistry(workspace)
    }

    if let focusedReplacement, focus.workspace != focusedReplacement {
        _ = setFocus(to: focusedReplacement.toLiveFocus())
    }
}

@MainActor
func focusReplacementForPrunedWorkspace(_ workspace: Workspace) -> Workspace? {
    let visibleWorkspaces = Workspace.all.filter { $0.isVisible && $0 != workspace }
    if let mainVisible = visibleWorkspaces.first(where: { $0 === mainMonitor.activeWorkspace }) {
        return mainVisible
    }
    return visibleWorkspaces.first { $0.projectId == workspace.projectId } ?? visibleWorkspaces.first
}

@MainActor
func workspaceShouldSurviveReconciliation(
    _ workspace: Workspace,
    retainedEmptyWorkspaceIds: [WorkspaceScope: WorkspaceId],
) -> Bool {
    guard !workspace.isArchived else { return false }
    return workspace.isVisible ||
        workspaceHasLifecycleWindows(workspace) ||
        workspace.isConfiguredPersistent ||
        projectWorkspaces(projectId: workspace.projectId).filter { !$0.isArchived }.count == 1 ||
        retainedEmptyWorkspaceIds[WorkspaceScope(projectId: workspace.projectId)] == workspace.id
}

@MainActor
func replacementWorkspaceForPrunedWorkspace(
    _ workspace: Workspace,
    retainedEmptyWorkspaceIds: [WorkspaceScope: WorkspaceId],
) -> Workspace? {
    let scope = WorkspaceScope(projectId: workspace.projectId)
    if let retainedWorkspaceId = retainedEmptyWorkspaceIds[scope],
       retainedWorkspaceId != workspace.id,
       let retainedWorkspace = winMuxWorkspaceState.workspaceById[retainedWorkspaceId],
       workspaceIsAvailableForMonitor(retainedWorkspace, monitor: workspace.workspaceMonitor)
    {
        return retainedWorkspace
    }
    if let candidate = orderedWorkspaces(in: scope).first(where: {
        $0.id != workspace.id &&
            workspaceShouldSurviveReconciliation($0, retainedEmptyWorkspaceIds: retainedEmptyWorkspaceIds) &&
            (workspaceHasSidebarVisibleWindows($0) || $0.isConfiguredPersistent) &&
            workspaceIsAvailableForMonitor($0, monitor: workspace.workspaceMonitor)
    }) {
        return candidate
    }
    if workspace.isVisible {
        return createBlankWorkspace(projectId: workspace.projectId, monitor: workspace.workspaceMonitor)
    }
    return nil
}

@MainActor
func ensureVisibleActiveProjectWorkspaces() {
    for monitor in monitors where winMuxWorkspaceState.visibleWorkspace(for: monitor) == nil {
        let viewportId = MonitorViewportId(monitor)
        let projectId = fallbackProjectIdForMissingActiveWorkspace(on: viewportId)
        let workspace = availablePreferredWorkspace(projectId: projectId, monitor: monitor)
            ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
        check(monitor.setActiveWorkspace(workspace))
    }
}

@MainActor
private func fallbackProjectIdForMissingActiveWorkspace(on viewportId: MonitorViewportId) -> WorkspaceProjectId {
    guard let viewport = winMuxWorkspaceState.monitorViewportsById[viewportId] else {
        return workspaceProjectDefaultId
    }
    if let previousProjectId = viewport.previousWorkspaceId.flatMap({ winMuxWorkspaceState.workspaceById[$0]?.projectId }) {
        return previousProjectId
    }
    if let rememberedProjectId = viewport.lastActiveWorkspaceByProject
        .sorted(by: { $0.key < $1.key })
        .first(where: { entry in winMuxWorkspaceState.workspaceById[entry.value] != nil })?
        .key
    {
        return rememberedProjectId
    }
    return workspaceProjectDefaultId
}

@MainActor
func availablePreferredWorkspace(projectId: WorkspaceProjectId, monitor: Monitor) -> Workspace? {
    orderedWorkspacesForPresentation()
        .filter { $0.projectId == projectId }
        .filter { !$0.isArchived }
        .filter { isValidAssignment(workspace: $0, screen: monitor.rect.topLeftCorner) }
        .first { workspaceIsAvailableForMonitor($0, monitor: monitor) }
}

@MainActor
func workspaceIsAvailableForMonitor(_ workspace: Workspace, monitor: Monitor) -> Bool {
    isValidAssignment(workspace: workspace, screen: monitor.rect.topLeftCorner) &&
        (!workspace.isVisible || workspace.workspaceMonitor.rect.topLeftCorner == monitor.rect.topLeftCorner)
}

@MainActor
func repairInvalidVisibleWorkspaceAssignments() {
    let invalidVisibleWorkspaces = winMuxWorkspaceState.monitorViewportsById.compactMap { viewportId, viewport -> Workspace? in
        guard let workspaceId = viewport.activeWorkspaceId,
              let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
              !isValidAssignment(workspace: workspace, screen: viewportId.topLeftCorner)
        else {
            return nil
        }
        return workspace
    }

    for workspace in invalidVisibleWorkspaces {
        if let forceAssignedMonitor = workspace.forceAssignedMonitor {
            _ = activateWorkspaceOnMonitorPreservingSourceViewport(workspace, targetMonitor: forceAssignedMonitor)
        }
    }

    for (viewportId, viewport) in winMuxWorkspaceState.monitorViewportsById {
        guard let workspaceId = viewport.activeWorkspaceId,
              let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
              !isValidAssignment(workspace: workspace, screen: viewportId.topLeftCorner)
        else {
            continue
        }
        var viewport = viewport
        viewport.activeWorkspaceId = nil
        if viewport.previousWorkspaceId == workspaceId {
            viewport.previousWorkspaceId = nil
        }
        winMuxWorkspaceState.monitorViewportsById[viewportId] = viewport
    }
}
