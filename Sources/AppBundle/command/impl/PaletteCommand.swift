import AppKit
import Common

struct PaletteCommand: Command {
    let args: PaletteCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        await SwitcherPalettePanel.shared.toggle()
        return true
    }
}
