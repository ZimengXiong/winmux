import AppKit

extension WindowMouseInteractionDriver {
    func beginStableResizePreviewFrame(for window: Window) {
        guard let workspace = window.nodeWorkspace else { return }
        WindowResizePreviewPanel.shared.beginStableFrame(workspace.workspaceMonitor.rect.toAppKitScreenRect)
    }

    func updateResizePreviewIfNeeded(window: Window, rect: Rect, force: Bool = false) {
        guard force || resizePreviewHasVisibleChange(from: lastRenderedResizePreviewRect, to: rect) else { return }
        lastRenderedResizePreviewRect = rect
        updateCompositedResizePreview(window, rect: rect)
    }
}

func resizePreviewHasVisibleChange(from previous: Rect?, to next: Rect) -> Bool {
    guard let previous else { return true }
    return abs(previous.topLeftX - next.topLeftX) >= resizePreviewVisibleChangeThreshold ||
        abs(previous.topLeftY - next.topLeftY) >= resizePreviewVisibleChangeThreshold ||
        abs(previous.width - next.width) >= resizePreviewVisibleChangeThreshold ||
        abs(previous.height - next.height) >= resizePreviewVisibleChangeThreshold
}
