import Common

extension CmdArgs {
    @MainActor
    func resolveTargetOrReportError(_ env: CmdEnv, _ io: CmdIo) -> LiveFocus? {
        // Flags
        if let windowId {
            if let wi = Window.get(byId: windowId) {
                return wi.toLiveFocusOrReportError(io)
            } else {
                io.err("Invalid <window-id> \(windowId) passed to --window-id")
                return nil
            }
        }
        if let workspaceName {
            guard let workspace = Workspace.existing(byName: workspaceName.raw) else {
                io.err("Workspace '\(workspaceName.raw)' doesn't exist")
                return nil
            }
            return workspace.toLiveFocus()
        }
        // Env
        if let windowId = env.windowId {
            if let wi = Window.get(byId: windowId) {
                return wi.toLiveFocusOrReportError(io)
            } else {
                io.err("Invalid <window-id> \(windowId) specified in \(AEROSPACE_WINDOW_ID) env variable")
                return nil
            }
        }
        if let wsName = env.workspaceName {
            guard let workspace = Workspace.existing(byName: wsName) else {
                io.err("Workspace '\(wsName)' doesn't exist")
                return nil
            }
            return workspace.toLiveFocus()
        }
        // Real Focus
        return focus
    }
}

extension Window {
    @MainActor
    func toLiveFocusOrReportError(_ io: CmdIo) -> LiveFocus? {
        if let result = toLiveFocusOrNil() {
            return result
        } else {
            io.err("Window \(windowId) doesn't belong to any monitor. And thus can't even define a focused workspace")
            return nil
        }
    }
}
