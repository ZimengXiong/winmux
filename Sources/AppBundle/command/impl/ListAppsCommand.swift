import AppKit
import Common

struct ListAppsCommand: Command {
    let args: ListAppsCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        var result = Array(MacApp.allAppsMap.values)
        if let hidden = args.macosHidden {
            result = result.filter { $0.nsApp.isHidden == hidden }
        }

        if args.outputOnlyCount {
            return io.out("\(result.count)")
        } else {
            return result.map { FormatObject.app($0) }.writeFormattedOutput(
                to: io,
                format: args.format,
                json: args.json,
                ignoreRightPaddingVar: args._format.isEmpty,
            )
        }
    }
}
