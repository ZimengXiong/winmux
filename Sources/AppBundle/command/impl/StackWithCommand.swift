import AppKit
import Common

struct StackWithCommand: Command {
    let args: StackWithCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let currentWindow = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        let direction = args.direction.val
        guard let (parent, ownIndex) = currentWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) else {
            return io.err("No windows in the specified direction")
        }
        guard let targetWindow = parent.children[ownIndex + direction.focusOffset].findLeafWindowRecursive(snappedTo: direction.opposite) else {
            return io.err("No windows in the specified direction")
        }
        createOrAppendWindowTabStack(sourceWindow: currentWindow, onto: targetWindow)
        return true
    }
}
