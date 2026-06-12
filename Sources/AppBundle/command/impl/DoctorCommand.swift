import AppKit
import Common

struct DoctorCommand: Command {
    let args: DoctorCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        io.out("WinMux doctor — git \(gitShortHash)")
        io.out("")

        io.out("Permissions:")
        io.out("  accessibility: \(AXIsProcessTrusted() ? "granted" : "MISSING (required)")")
        io.out("  screen capture: \(CGPreflightScreenCaptureAccess() ? "granted" : "missing (tab previews / radius estimation degraded)")")
        io.out("")

        io.out("Monitors (system window corner radius: \(systemWindowCornerRadius())pt):")
        for monitor in sortedMonitors {
            let active = monitor.activeWorkspace.name
            io.out("  [\(monitor.monitorAppKitNsScreenScreensId)] \(monitor.name) \(Int(monitor.rect.width))x\(Int(monitor.rect.height))\(monitor.isMain ? " (main)" : "") activeWorkspace=\(active)")
        }
        io.out("")

        let workspaces = Workspace.all
        io.out("State: \(workspaces.count) workspaces, \(MacWindow.allWindows.count) windows, focus=\(focus.windowOrNil?.windowId.description ?? "none") (workspace \(focus.workspace.name))")
        io.out("")

        // Per-app AX latency: time a trivial round-trip to each app's AX thread. Apps near the
        // 1s messaging timeout are the ones that make the whole system feel slow.
        io.out("Per-app AX latency (slowest first):")
        var rows: [(name: String, ms: Double, windows: Int)] = []
        for (_, app) in MacApp.allAppsMap {
            let name = app.nsApp.localizedName ?? app.rawAppBundleId ?? String(app.pid)
            let start = ContinuousClock.now
            let windowCount = (try? await app.getAxWindowsCount()) ?? -1
            let elapsed = start.duration(to: ContinuousClock.now)
            let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            rows.append((name, ms, windowCount))
        }
        for row in rows.sorted(by: { $0.ms > $1.ms }) {
            let flag = row.ms > 100 ? "  <-- SLOW" : ""
            let windows = row.windows >= 0 ? "\(row.windows)" : "error"
            io.out("  \(String(format: "%7.1f", row.ms))ms  \(row.name) (\(windows) ax windows)\(flag)")
        }
        return true
    }
}
