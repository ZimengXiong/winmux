import AppKit

/// Reads the current frame first and returns before the AXEnhancedUserInterface round-trip when
/// the frame already matches: layout re-asserts frames constantly and the vast majority of these
/// calls are no-ops, so the no-op path must not pay the disableAnimations read.
func setFrame(_ window: AXUIElement, app: AXUIElement, _ topLeft: CGPoint?, _ size: CGSize?, _ job: RunLoopJob) throws {
    let currentTopLeft: CGPoint? = topLeft == nil ? nil : window.get(Ax.topLeftCornerAttr)
    let currentSize: CGSize? = size == nil ? nil : window.get(Ax.sizeAttr)
    let positionMatches = topLeft == nil || currentTopLeft == topLeft
    let sizeMatches = size == nil || currentSize == size
    if positionMatches && sizeMatches {
        return
    }
    try disableAnimations(app: app, job) {
        if let size { window.set(Ax.sizeAttr, size) }
        try job.checkCancellation()
        if let topLeft { window.set(Ax.topLeftCornerAttr, topLeft) } else { return }
        try job.checkCancellation()
        // Moving a window can make macOS clamp its size (e.g. crossing monitors), so the size may
        // need re-asserting. Only re-set when it actually changed: an AX read is much cheaper than
        // an unconditional write, which forces a second layout pass in the target app every time.
        if let size, window.get(Ax.sizeAttr) != size { window.set(Ax.sizeAttr, size) }
    }
}

func disableAnimations<T>(app: AXUIElement, _ job: RunLoopJob, _ body: () throws -> T) throws -> T {
    let wasEnabled = app.get(Ax.enhancedUserInterfaceAttr) == true
    if wasEnabled {
        app.set(Ax.enhancedUserInterfaceAttr, false)
    }
    defer {
        if wasEnabled {
            app.set(Ax.enhancedUserInterfaceAttr, true)
        }
    }
    try job.checkCancellation()
    return try body()
}
