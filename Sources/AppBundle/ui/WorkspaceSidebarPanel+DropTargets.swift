import AppKit

extension WorkspaceSidebarPanel {
    func updateDropTargets(_ targets: [WorkspaceSidebarDropTargetFrame]) {
        workspaceSidebarDropTargets = convertDropTargets(targets)
    }

    func convertDropTargets(_ targets: [WorkspaceSidebarDropTargetFrame]) -> [WorkspaceSidebarDropTarget] {
        targets.compactMap { target in
            let windowRect = hostingView.convert(target.frame, to: nil)
            let screenRect = convertToScreen(windowRect)
            return WorkspaceSidebarDropTarget(kind: target.kind, rect: screenRect.monitorFrameNormalized())
        }
    }

    func visibleScreenRectNormalized() -> Rect? {
        guard isVisible, viewModel.workspaceSidebarVisibleWidth > 0 else { return nil }
        return CGRect(
            x: frame.minX,
            y: frame.minY,
            width: min(viewModel.workspaceSidebarVisibleWidth, frame.width),
            height: frame.height,
        ).monitorFrameNormalized()
    }
}
