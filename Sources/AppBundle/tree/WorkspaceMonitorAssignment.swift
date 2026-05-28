import AppKit
import Common

extension Monitor {
    @MainActor
    var activeWorkspace: Workspace {
        if let existing = winMuxWorkspaceState.visibleWorkspace(for: self) {
            return existing
        }
        rearrangeWorkspacesOnMonitors()
        return self.activeWorkspace
    }

    @MainActor
    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        rect.topLeftCorner.setActiveWorkspace(workspace)
    }
}

@MainActor
func activateWorkspaceOnMonitorPreservingSourceViewport(_ workspace: Workspace, targetMonitor: Monitor) -> Bool {
    let sourceMonitor = workspace.isVisible ? workspace.workspaceMonitor : nil
    let sourceProjectId = workspace.projectId
    if let sourceMonitor,
       sourceMonitor.rect.topLeftCorner != targetMonitor.rect.topLeftCorner
    {
        let fallbackWorkspace = getOrCreateMonitorViewportFallbackWorkspace(
            projectId: sourceProjectId,
            for: sourceMonitor,
            excluding: workspace,
        )
        check(
            sourceMonitor.setActiveWorkspace(fallbackWorkspace),
            "Generated incompatible fallback workspace (\(fallbackWorkspace)) for the monitor (\(sourceMonitor))",
        )
    }
    guard targetMonitor.setActiveWorkspace(workspace) else { return false }
    return true
}

@MainActor
func overrideWorkspaceOnMonitorBySwappingActiveViewports(_ workspace: Workspace, targetMonitor: Monitor) -> Bool {
    guard isValidAssignment(workspace: workspace, screen: targetMonitor.rect.topLeftCorner) else {
        return false
    }
    guard workspace.isVisible else {
        return targetMonitor.setActiveWorkspace(workspace)
    }

    let sourceMonitor = workspace.workspaceMonitor
    guard sourceMonitor.rect.topLeftCorner != targetMonitor.rect.topLeftCorner else {
        return true
    }

    let sourceReplacement = nearestWorkspaceForOverrideSourceMonitor(
        excluding: workspace,
        sourceMonitor: sourceMonitor,
        targetMonitor: targetMonitor,
    )
    if let sourceReplacement {
        _ = winMuxWorkspaceState.setActiveWorkspace(sourceReplacement, on: MonitorViewportId(sourceMonitor))
    } else {
        let fallback = createBlankWorkspace(projectId: workspace.projectId, monitor: sourceMonitor)
        _ = winMuxWorkspaceState.setActiveWorkspace(fallback, on: MonitorViewportId(sourceMonitor))
    }
    _ = winMuxWorkspaceState.setActiveWorkspace(workspace, on: MonitorViewportId(targetMonitor))
    checkWorkspaceHierarchyInvariants()
    return true
}

@MainActor
func nearestWorkspaceForOverrideSourceMonitor(
    excluding workspace: Workspace,
    sourceMonitor: Monitor,
    targetMonitor: Monitor,
) -> Workspace? {
    let candidates = orderedWorkspacesForPresentation()
        .filter { candidate in
            candidate.projectId == workspace.projectId &&
                candidate != workspace &&
                !candidate.isArchived &&
                isValidAssignment(workspace: candidate, screen: sourceMonitor.rect.topLeftCorner) &&
                (!candidate.isVisible || candidate.workspaceMonitor.rect.topLeftCorner == targetMonitor.rect.topLeftCorner)
        }
    guard let workspaceIndex = orderedWorkspacesForPresentation().firstIndex(of: workspace) else {
        return candidates.first
    }
    return candidates.min {
        abs((orderedWorkspacesForPresentation().firstIndex(of: $0) ?? Int.max) - workspaceIndex) <
            abs((orderedWorkspacesForPresentation().firstIndex(of: $1) ?? Int.max) - workspaceIndex)
    }
}

@MainActor
func gcMonitors() {
    rearrangeWorkspacesOnMonitors()
}

extension CGPoint {
    @MainActor
    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        if !isValidAssignment(workspace: workspace, screen: self) {
            return false
        }
        let viewportId = MonitorViewportId(topLeftCorner: self)
        guard !winMuxWorkspaceState.isWorkspaceActive(workspace.id, outside: viewportId) else {
            return false
        }
        _ = winMuxWorkspaceState.setActiveWorkspace(workspace, on: viewportId)
        checkWorkspaceHierarchyInvariants()
        return true
    }
}

@MainActor
func checkWorkspaceHierarchyInvariants(requireActiveMonitorViewports: Bool = false) {
    for workspace in Workspace.all {
        check(winMuxWorkspaceState.projectsById[workspace.projectId] != nil, "Workspace '\(workspace.name)' references missing project '\(workspace.projectId)'")
    }

    for (viewportId, viewport) in winMuxWorkspaceState.monitorViewportsById {
        if let activeWorkspaceId = viewport.activeWorkspaceId {
            check(winMuxWorkspaceState.workspaceById[activeWorkspaceId] != nil, "Display viewport '\(viewportId)' references missing workspace '\(activeWorkspaceId)'")
            check(!winMuxWorkspaceState.isWorkspaceActive(activeWorkspaceId, outside: viewportId), "Workspace '\(activeWorkspaceId)' is active on more than one display viewport")
            if let workspace = winMuxWorkspaceState.workspaceById[activeWorkspaceId] {
                check(isValidAssignment(workspace: workspace, screen: viewportId.topLeftCorner), "Display viewport '\(viewportId)' has incompatible active workspace '\(workspace.name)'")
            }
        }
    }

    guard requireActiveMonitorViewports else { return }
    for monitor in monitors {
        let viewportId = MonitorViewportId(monitor)
        guard let viewport = winMuxWorkspaceState.monitorViewportsById[viewportId],
              let activeWorkspaceId = viewport.activeWorkspaceId,
              let workspace = winMuxWorkspaceState.workspaceById[activeWorkspaceId]
        else {
            check(false, "Current monitor viewport '\(viewportId)' has no active workspace after reconciliation")
            continue
        }
        check(isValidAssignment(workspace: workspace, screen: viewportId.topLeftCorner), "Current monitor viewport '\(viewportId)' has incompatible active workspace '\(workspace.name)'")
    }
}

@MainActor
func rearrangeWorkspacesOnMonitors() {
    let oldViewportsById = winMuxWorkspaceState.monitorViewportsById
    let currentMonitorIds = Set(monitors.map(MonitorViewportId.init))
    let activeViewportIds = Set(oldViewportsById.compactMap { viewportId, viewport -> MonitorViewportId? in
        guard let workspaceId = viewport.activeWorkspaceId,
              let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
              isValidAssignment(workspace: workspace, screen: viewportId.topLeftCorner)
        else { return nil }
        return viewportId
    })
    if activeViewportIds == currentMonitorIds {
        return
    }

    var oldVisibleMonitors: Set<MonitorViewportId> = oldViewportsById.compactMap { viewportId, viewport in
        guard let activeWorkspaceId = viewport.activeWorkspaceId,
              winMuxWorkspaceState.workspaceById[activeWorkspaceId] != nil
        else { return nil }
        return viewportId
    }.toSet()

    let newMonitors = monitors.map(MonitorViewportId.init)
    var newMonitorToOldMonitorMapping: [MonitorViewportId: MonitorViewportId] = [:]
    for newMonitor in newMonitors where oldVisibleMonitors.contains(newMonitor) {
        check(oldVisibleMonitors.remove(newMonitor) != nil)
        newMonitorToOldMonitorMapping[newMonitor] = newMonitor
    }
    for newMonitor in newMonitors {
        if newMonitorToOldMonitorMapping[newMonitor] != nil { continue }
        if let oldMonitor = oldVisibleMonitors.minBy({ ($0.topLeftCorner - newMonitor.topLeftCorner).vectorLength }) {
            check(oldVisibleMonitors.remove(oldMonitor) != nil)
            newMonitorToOldMonitorMapping[newMonitor] = oldMonitor
        }
    }

    winMuxWorkspaceState.monitorViewportsById = [:]

    for newMonitor in newMonitors {
        let newScreen = newMonitor.topLeftCorner
        let mappedOldMonitor = newMonitorToOldMonitorMapping[newMonitor]
        let preservedViewport = mappedOldMonitor.flatMap { oldViewportsById[$0] } ?? oldViewportsById[newMonitor]
        if var preservedViewport {
            preservedViewport = MonitorViewport(
                id: newMonitor,
                activeWorkspaceId: nil,
                previousWorkspaceId: preservedViewport.previousWorkspaceId,
                lastActiveWorkspaceByProject: preservedViewport.lastActiveWorkspaceByProject,
            )
            winMuxWorkspaceState.monitorViewportsById[newMonitor] = preservedViewport
        }
        let existingVisibleWorkspace = mappedOldMonitor
            .flatMap { oldViewportsById[$0]?.activeWorkspaceId }
            .flatMap { winMuxWorkspaceState.workspaceById[$0] }
        if let existingVisibleWorkspace,
           newScreen.setActiveWorkspace(existingVisibleWorkspace)
        {
            continue
        }
        let projectId = existingVisibleWorkspace?.projectId ?? workspaceProjectDefaultId
        let workspace = getOrCreateFallbackWorkspace(
            projectId: projectId,
            monitor: newScreen.monitorApproximation,
            excluding: existingVisibleWorkspace,
        )
        check(newScreen.setActiveWorkspace(workspace),
              "Generated incompatible fallback workspace (\(workspace)) for the display viewport (\(newScreen)")
    }
}

@MainActor
func isValidAssignment(workspace: Workspace, screen: CGPoint) -> Bool {
    isValidAssignment(workspaceName: workspace.name, screen: screen)
}

@MainActor
func isValidAssignment(workspaceName: String, screen: CGPoint) -> Bool {
    if let forceAssigned = resolvedForceAssignedMonitor(forWorkspaceName: workspaceName), forceAssigned.rect.topLeftCorner != screen {
        return false
    } else {
        return true
    }
}
