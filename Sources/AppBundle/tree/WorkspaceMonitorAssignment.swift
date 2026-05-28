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
func activateWorkspaceOnMonitorPreservingSourceLane(_ workspace: Workspace, targetMonitor: Monitor) -> Bool {
    let sourceMonitor = workspace.isVisible ? workspace.workspaceMonitor : nil
    let sourceProjectId = workspace.projectId
    if let sourceMonitor,
       sourceMonitor.rect.topLeftCorner != targetMonitor.rect.topLeftCorner
    {
        let fallbackWorkspace = getOrCreateLaneFallbackWorkspace(
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
func overrideWorkspaceOnMonitorBySwappingActiveLanes(_ workspace: Workspace, targetMonitor: Monitor) -> Bool {
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
        _ = winMuxWorkspaceState.setActiveWorkspace(sourceReplacement, on: DisplayLaneId(sourceMonitor))
    } else {
        let fallback = createBlankWorkspace(projectId: workspace.projectId, monitor: sourceMonitor)
        _ = winMuxWorkspaceState.setActiveWorkspace(fallback, on: DisplayLaneId(sourceMonitor))
    }
    _ = winMuxWorkspaceState.setActiveWorkspace(workspace, on: DisplayLaneId(targetMonitor))
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
        let laneId = DisplayLaneId(topLeftCorner: self)
        guard !winMuxWorkspaceState.isWorkspaceActive(workspace.id, outside: laneId) else {
            return false
        }
        _ = winMuxWorkspaceState.setActiveWorkspace(workspace, on: laneId)
        checkWorkspaceHierarchyInvariants()
        return true
    }
}

@MainActor
func checkWorkspaceHierarchyInvariants() {
    for workspace in Workspace.all {
        check(winMuxWorkspaceState.projectsById[workspace.projectId] != nil, "Workspace '\(workspace.name)' references missing project '\(workspace.projectId)'")
    }

    for (laneId, lane) in winMuxWorkspaceState.lanesById {
        if let activeWorkspaceId = lane.activeWorkspaceId {
            check(winMuxWorkspaceState.workspaceById[activeWorkspaceId] != nil, "Display lane '\(laneId)' references missing workspace '\(activeWorkspaceId)'")
        }
    }
}

@MainActor
func rearrangeWorkspacesOnMonitors() {
    let oldLanesById = winMuxWorkspaceState.lanesById
    let currentMonitorIds = Set(monitors.map(DisplayLaneId.init))
    let activeLaneIds = Set(oldLanesById.compactMap { laneId, lane -> DisplayLaneId? in
        guard let workspaceId = lane.activeWorkspaceId,
              let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
              isValidAssignment(workspace: workspace, screen: laneId.topLeftCorner)
        else { return nil }
        return laneId
    })
    if activeLaneIds == currentMonitorIds {
        return
    }

    var oldVisibleMonitors: Set<DisplayLaneId> = oldLanesById.compactMap { laneId, lane in
        guard let activeWorkspaceId = lane.activeWorkspaceId,
              winMuxWorkspaceState.workspaceById[activeWorkspaceId] != nil
        else { return nil }
        return laneId
    }.toSet()

    let newMonitors = monitors.map(DisplayLaneId.init)
    var newMonitorToOldMonitorMapping: [DisplayLaneId: DisplayLaneId] = [:]
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

    winMuxWorkspaceState.lanesById = [:]

    for newMonitor in newMonitors {
        let newScreen = newMonitor.topLeftCorner
        let mappedOldMonitor = newMonitorToOldMonitorMapping[newMonitor]
        let existingVisibleWorkspace = mappedOldMonitor
            .flatMap { oldLanesById[$0]?.activeWorkspaceId }
            .flatMap { winMuxWorkspaceState.workspaceById[$0] }
        if let existingVisibleWorkspace,
           newScreen.setActiveWorkspace(existingVisibleWorkspace)
        {
            continue
        }
        let projectId = existingVisibleWorkspace?.projectId ?? workspaceProjectDefaultId
        let workspace = getOrCreateFallbackWorkspace(
            projectId: projectId,
            laneId: DisplayLaneId(topLeftCorner: newScreen),
            monitor: newScreen.monitorApproximation,
            excluding: existingVisibleWorkspace,
        )
        check(newScreen.setActiveWorkspace(workspace),
              "Generated incompatible fallback workspace (\(workspace)) for the display lane (\(newScreen)")
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
