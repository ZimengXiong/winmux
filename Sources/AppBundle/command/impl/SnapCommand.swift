import AppKit
import Common

struct SnapCommand: Command {
    let args: SnapCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard !config.enableWindowManagement else {
            return io.err("The 'snap' command is only available when enable-window-management = false")
        }
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else { return io.err(noWindowIsFocused) }

        let workspaceRect = target.workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        let targetRect = unmanagedSnapTargetRect(for: args.action.val.unmanagedSnapAction, in: workspaceRect)
        window.lastFloatingSize = targetRect.size
        window.lastKnownActualRect = targetRect
        window.setAxFrame(targetRect.topLeftCorner, targetRect.size)
        return true
    }
}

extension SnapCmdArgs.SnapAction {
    fileprivate var unmanagedSnapAction: UnmanagedWindowSnapAction {
        switch self {
            case .leftHalf: .leftHalf
            case .rightHalf: .rightHalf
            case .topHalf: .topHalf
            case .bottomHalf: .bottomHalf
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight: .bottomRight
            case .firstThird: .firstThird
            case .centerThird: .centerThird
            case .lastThird: .lastThird
            case .firstTwoThirds: .firstTwoThirds
            case .lastTwoThirds: .lastTwoThirds
            case .maximize: .maximize
        }
    }
}
