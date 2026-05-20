import Common

func automaticWorkspaceIndex(_ name: String) -> Int? {
    Int(name)
}

func internalAutomaticWorkspaceIndex(_ name: String) -> Int? {
    guard name.hasPrefix(internalAutomaticWorkspacePrefix) else { return nil }
    let suffix = name.replacingOccurrences(of: internalAutomaticWorkspacePrefix, with: "")
    return Int(suffix)
}

func lowestUnusedPositiveIndex(_ usedIndices: Set<Int>) -> Int {
    var candidate = 1
    while usedIndices.contains(candidate) {
        candidate += 1
    }
    return candidate
}

@MainActor
func nextInternalAutomaticWorkspaceName() -> String {
    let usedIndices = Set(winMuxWorkspaceState.workspaceIdByName.keys.compactMap(internalAutomaticWorkspaceIndex))
    return "\(internalAutomaticWorkspacePrefix)\(lowestUnusedPositiveIndex(usedIndices))"
}

@MainActor
func nextAutomaticWorkspaceDisplayIndex(projectId: WorkspaceProjectId, monitor: Monitor) -> Int {
    let usedIndices = orderedWorkspacesForPresentation()
        .filter { $0.projectId == projectId }
        .filter(\.usesAutomaticDisplayName)
        .compactMap { automaticWorkspaceDisplayIndex($0, focusedWorkspace: nil) }
        .toSet()
    return lowestUnusedPositiveIndex(usedIndices)
}

@MainActor
func nextAutomaticWorkspaceName(projectId _: WorkspaceProjectId = workspaceProjectDefaultId, monitor: Monitor = mainMonitor) -> String {
    var candidate = 1
    while true {
        let name = String(candidate)
        if winMuxWorkspaceState.workspaceIdByName[name] == nil,
           isValidAssignment(workspaceName: name, screen: monitor.rect.topLeftCorner)
        {
            return name
        }
        candidate += 1
    }
}

func parsePositiveWorkspaceDisplayIndex(_ workspaceName: String) -> Int? {
    guard let targetIndex = Int(workspaceName),
          targetIndex > 0,
          String(targetIndex) == workspaceName
    else {
        return nil
    }
    return targetIndex
}
