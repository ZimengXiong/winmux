import Common

struct ProjectCommand: Command {
    let args: ProjectCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let monitor = target.workspace.workspaceMonitor
        let currentProjectId = activeWorkspaceProjectId(for: monitor)
        guard let project = resolveProjectTarget(args.target.val, currentProjectId: currentProjectId, wrapAround: args.wrapAround) else {
            return io.err(projectTargetResolutionError(args.target.val))
        }
        if project.id == currentProjectId {
            if !args.failIfNoop {
                io.err("Project '\(project.name)' is already focused. Tip: use --fail-if-noop to exit with non-zero code")
            }
            return !args.failIfNoop
        }
        guard let workspace = switchWorkspaceProject(project.id, on: monitor) else {
            return io.err("Can't switch to project '\(project.name)'")
        }
        return workspace.focusWorkspace()
    }
}
