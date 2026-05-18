import AppKit

func setFrame(_ window: AXUIElement, _ topLeft: CGPoint?, _ size: CGSize?, _ job: RunLoopJob) throws {
    let currentTopLeft: CGPoint? = topLeft == nil ? nil : window.get(Ax.topLeftCornerAttr)
    let currentSize: CGSize? = size == nil ? nil : window.get(Ax.sizeAttr)
    let positionMatches = topLeft == nil || currentTopLeft == topLeft
    let sizeMatches = size == nil || currentSize == size
    if positionMatches && sizeMatches {
        return
    }
    if let size { window.set(Ax.sizeAttr, size) }
    try job.checkCancellation()
    if let topLeft { window.set(Ax.topLeftCornerAttr, topLeft) } else { return }
    try job.checkCancellation()
    if let size { window.set(Ax.sizeAttr, size) }
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
