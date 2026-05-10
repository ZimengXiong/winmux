import DeckCore
import Foundation

@MainActor
enum DeckProfileLaunchDestination {
    case newProject
    case currentProject
}

@MainActor
func launchDeckProfile(_ profileName: String, destination: DeckProfileLaunchDestination) {
    runWorkspaceSidebarSession {
        let storage = DeckStorage()
        let profileUrl = storage.profileUrl(for: profileName)
        let profile = try storage.loadProfile(profileName)
        let monitor = sidebarWorkspaceTargetMonitor()
        let project = try deckLaunchProject(
            for: profile,
            profileName: profileName,
            destination: destination,
            monitor: monitor,
        )
        holdFocusOnWorkspaceProject(project.id, for: deckLaunchFocusHoldDuration(for: profile))
        defer {
            scheduleDeckLaunchProjectFocusHoldClear(projectId: project.id)
        }
        TrayMenuModel.shared.workspaceSidebarSelectedProjectId = project.id

        let prepared = try prepareDeckProfile(profile, for: project, monitor: monitor)
        let launchWorkspaceName = prepared.actions.compactMap(\.route?.workspace).first
        focusDeckLaunchTarget(projectId: project.id, workspaceName: launchWorkspaceName, monitor: monitor)

        let report = try await DeckRunner().open(
            profile: prepared,
            profileUrl: profileUrl,
            options: DeckOpenOptions(enableWinMuxRouting: true),
        )
        focusDeckLaunchTarget(projectId: project.id, workspaceName: launchWorkspaceName, monitor: monitor)
        scheduleDeckLaunchTargetFocus(projectId: project.id, workspaceName: launchWorkspaceName, monitor: monitor)

        if let skippedRoutingReason = report.skippedRoutingReason {
            MessageModel.shared.message = Message(
                description: "Deck Routing Skipped",
                body: skippedRoutingReason,
            )
        }
    }
}

@MainActor
private func prepareDeckProfile(_ profile: DeckProfile, for project: WorkspaceProject, monitor: Monitor) throws -> DeckProfile {
    var workspaceNamesByLabel: [String: String] = [:]
    var routedLabels: [String] = []

    for action in profile.actions {
        guard let label = action.route?.workspace?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty,
              workspaceNamesByLabel[label] == nil
        else {
            continue
        }
        routedLabels.append(label)
    }

    for label in routedLabels {
        let workspace = createDeckRouteWorkspace(
            project: project,
            profile: profile,
            label: label,
            monitor: monitor,
        )
        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: label)
        workspaceNamesByLabel[label] = workspace.name
    }

    var prepared = profile
    prepared.actions = profile.actions.map { action in
        guard var route = action.route,
              let label = route.workspace,
              let workspaceName = workspaceNamesByLabel[label]
        else {
            return action
        }
        var routedAction = action
        route.workspace = workspaceName
        routedAction.route = route
        return routedAction
    }
    return prepared
}

@MainActor
private func createDeckRouteWorkspace(
    project: WorkspaceProject,
    profile: DeckProfile,
    label: String,
    monitor: Monitor,
) -> Workspace {
    let workspaceName = uniqueDeckWorkspaceName(profile: profile, project: project, label: label)
    let workspace = Workspace.get(byName: workspaceName)
    workspace.lifecycle = .durable
    workspace.restoreNamingStyle(.explicit)
    workspace.assignProject(project.id)
    workspace.assignLane(DisplayLaneId(monitor))
    return workspace
}

@MainActor
private func uniqueDeckWorkspaceName(profile: DeckProfile, project: WorkspaceProject, label: String) -> String {
    let profileName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = sanitizedDeckWorkspaceNameComponent(profileName.isEmpty ? project.name : profileName)
    let suffix = sanitizedDeckWorkspaceNameComponent(label)
    let base = suffix.isEmpty ? prefix : "\(prefix) - \(suffix)"
    let existingNames = Set(Workspace.all.map { $0.name.lowercased() })
    guard existingNames.contains(base.lowercased()) else { return base }

    for index in 2... {
        let candidate = "\(base) \(index)"
        if !existingNames.contains(candidate.lowercased()) {
            return candidate
        }
    }
    return base
}

private func sanitizedDeckWorkspaceNameComponent(_ raw: String) -> String {
    let collapsed = raw
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
        .split(separator: " ")
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return collapsed.isEmpty ? "Project Template" : collapsed
}

@MainActor
private func focusDeckLaunchTarget(projectId: WorkspaceProjectId, workspaceName: String?, monitor: Monitor) {
    TrayMenuModel.shared.workspaceSidebarSelectedProjectId = projectId
    if let workspaceName, let workspace = Workspace.existing(byName: workspaceName) {
        _ = workspace.focusWorkspace()
    } else if let workspace = switchWorkspaceProject(projectId, on: monitor) {
        _ = workspace.focusWorkspace()
    }
    updateTrayText()
    WorkspaceSidebarPanel.shared.refresh()
}

@MainActor
private func scheduleDeckLaunchTargetFocus(projectId: WorkspaceProjectId, workspaceName: String?, monitor: Monitor) {
    for delay in [0.25, 0.85] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            focusDeckLaunchTarget(projectId: projectId, workspaceName: workspaceName, monitor: monitor)
        }
    }
}

@MainActor
private func scheduleDeckLaunchProjectFocusHoldClear(projectId: WorkspaceProjectId) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        clearFocusOnWorkspaceProjectHold(projectId)
    }
}

private func deckLaunchFocusHoldDuration(for profile: DeckProfile) -> TimeInterval {
    let routingTimeout = profile.actions.compactMap(\.route?.timeoutSeconds).max() ?? 0
    let launchBudget = TimeInterval(profile.actions.count * 5)
    return min(max(60, routingTimeout + launchBudget + 10), 300)
}

@MainActor
private func deckLaunchProject(
    for profile: DeckProfile,
    profileName: String,
    destination: DeckProfileLaunchDestination,
    monitor: Monitor,
) throws -> WorkspaceProject {
    switch destination {
        case .newProject:
            let project = createWorkspaceProject()
            let projectName = uniqueDeckProjectName(profile.name.isEmpty ? profileName : profile.name)
            try renameWorkspaceProject(project.id, displayName: projectName)
            return winMuxWorkspaceState.projectsById[project.id] ?? project
        case .currentProject:
            let projectId = sidebarWorkspaceTargetProjectId(targetMonitor: monitor)
            materializePersistedWorkspaceProjects()
            guard let project = winMuxWorkspaceState.projectsById[projectId] else {
                throw WorkspaceMutationError.projectNotFound(projectId.rawValue)
            }
            return project
    }
}

@MainActor
private func uniqueDeckProjectName(_ baseName: String) -> String {
    let trimmedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = trimmedBaseName.isEmpty ? "Deck Project" : trimmedBaseName
    let existingNames = Set(workspaceProjects().map { $0.name.lowercased() })
    guard existingNames.contains(base.lowercased()) else { return base }

    for index in 2... {
        let candidate = "\(base) \(index)"
        if !existingNames.contains(candidate.lowercased()) {
            return candidate
        }
    }
    return base
}
