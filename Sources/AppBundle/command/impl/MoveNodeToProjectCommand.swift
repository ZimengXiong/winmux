import Common

struct MoveNodeToProjectCommand: Command {
    let args: MoveNodeToProjectCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else { return io.err(noWindowIsFocused) }
        guard let sourceWorkspace = window.nodeWorkspace else {
            return io.err("Window \(window.windowId) doesn't belong to any workspace")
        }
        guard let project = resolveProjectTarget(args.target.val, currentProjectId: sourceWorkspace.projectId, wrapAround: args.wrapAround) else {
            return io.err(projectTargetResolutionError(args.target.val))
        }
        let monitor = window.nodeMonitor ?? sourceWorkspace.workspaceMonitor
        let targetWorkspace = firstWorkspaceForProjectMove(projectId: project.id, monitor: monitor)
        return moveWindowToWorkspace(
            window,
            targetWorkspace,
            io,
            focusFollowsWindow: args.focusFollowsWindow,
            failIfNoop: args.failIfNoop,
            index: INDEX_BIND_LAST,
        )
    }
}

@MainActor
func resolveProjectTarget(
    _ target: ProjectTarget,
    currentProjectId: WorkspaceProjectId,
    wrapAround: Bool,
) -> WorkspaceProject? {
    let projects = workspaceProjects()
    guard !projects.isEmpty else { return nil }
    switch target {
        case .index(let index):
            return projects.getOrNil(atIndex: index - 1)
        case .directId(let id):
            return projects.first { $0.id.rawValue == id }
        case .relative(let nextPrev):
            guard let currentIndex = projects.firstIndex(where: { $0.id == currentProjectId }) else { return nil }
            let targetIndex = currentIndex + (nextPrev == .next ? 1 : -1)
            return wrapAround ? projects.get(wrappingIndex: targetIndex) : projects.getOrNil(atIndex: targetIndex)
    }
}

func projectTargetResolutionError(_ target: ProjectTarget) -> String {
    switch target {
        case .directId(let id): "Project '\(id)' doesn't exist"
        case .index(let index): "Project index \(index) is out of range"
        case .relative: "Can't resolve project target"
    }
}

@MainActor
private func firstWorkspaceForProjectMove(projectId: WorkspaceProjectId, monitor: Monitor) -> Workspace {
    availablePreferredWorkspace(projectId: projectId, monitor: monitor)
        ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
}
