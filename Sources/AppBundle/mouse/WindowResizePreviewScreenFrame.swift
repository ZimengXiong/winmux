import AppKit

func windowResizePreviewAllScreensFrame() -> CGRect? {
    guard let first = NSScreen.screens.first?.frame else { return nil }
    let union = NSScreen.screens.dropFirst().reduce(first) { $0.union($1.frame) }
    return union.insetBy(dx: -128, dy: -128)
}
