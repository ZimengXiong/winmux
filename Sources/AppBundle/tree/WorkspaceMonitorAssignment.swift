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
    guard targetMonitor.setActiveWorkspace(workspace) else { return false }

    if let sourceMonitor,
       sourceMonitor.rect.topLeftCorner != targetMonitor.rect.topLeftCorner
    {
        let fallbackWorkspace = getOrCreateLaneFallbackWorkspace(projectId: sourceProjectId, for: sourceMonitor)
        check(
            sourceMonitor.setActiveWorkspace(fallbackWorkspace),
            "Generated incompatible fallback workspace (\(fallbackWorkspace)) for the monitor (\(sourceMonitor))",
        )
    }
    return true
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
    var oldVisibleMonitors: Set<DisplayLaneId> = oldLanesById.compactMap { laneId, lane in
        guard let activeWorkspaceId = lane.activeWorkspaceId,
              winMuxWorkspaceState.workspaceById[activeWorkspaceId] != nil
        else { return nil }
        return laneId
    }.toSet()

    let newMonitors = monitors.map(DisplayLaneId.init)
    var newMonitorToOldMonitorMapping: [DisplayLaneId: DisplayLaneId] = [:]
    for newMonitor in newMonitors {
        if let oldMonitor = oldVisibleMonitors.minBy({ ($0.topLeftCorner - newMonitor.topLeftCorner).vectorLength }) {
            check(oldVisibleMonitors.remove(oldMonitor) != nil)
            newMonitorToOldMonitorMapping[newMonitor] = oldMonitor
        }
    }

    winMuxWorkspaceState.lanesById = [:]

    for newMonitor in newMonitors {
        let newScreen = newMonitor.topLeftCorner
        if let existingVisibleWorkspace = newMonitorToOldMonitorMapping[newMonitor]
            .flatMap({ oldLanesById[$0]?.activeWorkspaceId })
            .flatMap({ winMuxWorkspaceState.workspaceById[$0] }),
           newScreen.setActiveWorkspace(existingVisibleWorkspace)
        {
            continue
        }
        let workspace = getOrCreateLaneFallbackWorkspace(forPoint: newScreen)
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
