import AppKit
import Common

struct WindowResizePreviewLayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps
    let weightMap: WindowResizePreviewWeightMap

    @MainActor
    init(workspace: Workspace, weightMap: WindowResizePreviewWeightMap) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
        self.weightMap = weightMap
    }

    @MainActor
    func weight(for node: TreeNode, orientation: Orientation) -> CGFloat {
        weightMap.weight(for: node, orientation: orientation)
    }
}
