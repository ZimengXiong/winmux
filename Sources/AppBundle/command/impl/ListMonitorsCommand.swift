import AppKit
import Common

struct ListMonitorsCommand: Command {
    let args: ListMonitorsCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        let focus = focus
        var result = sortedMonitors
        if let focused = args.focused {
            result = result.filter { (monitor) in (monitor.activeWorkspace == focus.workspace) == focused }
        }
        if let mouse = args.mouse {
            let mouseWorkspace = mouseLocation.monitorApproximation.activeWorkspace
            result = result.filter { (monitor) in (monitor.activeWorkspace == mouseWorkspace) == mouse }
        }

        if args.outputOnlyCount {
            return io.out("\(result.count)")
        } else {
            return result.map { FormatObject.monitor($0) }.writeFormattedOutput(
                to: io,
                format: args.format,
                json: args.json,
                ignoreRightPaddingVar: args._format.isEmpty,
            )
        }
    }
}
