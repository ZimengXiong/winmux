import Common

struct OpenSidebarCommand: Command {
    let args: OpenSidebarCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    @MainActor
    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        openWorkspaceSidebarFromCommand()
        return true
    }
}
