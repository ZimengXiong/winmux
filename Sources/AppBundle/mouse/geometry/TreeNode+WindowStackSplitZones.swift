import Common

extension TreeNode {
    @MainActor
    func stackSplitDropZoneRect(position: WindowStackSplitPosition) -> Rect? {
        guard let centeredBodyRect = centeredBodyDropZoneRect,
              let sideBodyRect = sideBodyDropZoneRect,
              let swapRect = swapDropZoneRect
        else { return nil }
        return stackSplitDropZoneRect(
            position: position,
            centeredBodyRect: centeredBodyRect,
            sideBodyRect: sideBodyRect,
            swapRect: swapRect,
        )
    }

    @MainActor
    func stackSplitPreviewRect(position: WindowStackSplitPosition) -> Rect? {
        windowDragVisibleRect?.stackSplitPreviewRect(position: position)
    }

    private func stackSplitDropZoneRect(
        position: WindowStackSplitPosition,
        centeredBodyRect: Rect,
        sideBodyRect: Rect,
        swapRect: Rect,
    ) -> Rect? {
        switch position {
            case .left:
                return leftStackSplitDropZone(sideBodyRect: sideBodyRect, swapRect: swapRect)
            case .right:
                return rightStackSplitDropZone(sideBodyRect: sideBodyRect, swapRect: swapRect)
            case .above:
                return aboveStackSplitDropZone(centeredBodyRect: centeredBodyRect, swapRect: swapRect)
            case .below:
                return belowStackSplitDropZone(centeredBodyRect: centeredBodyRect, swapRect: swapRect)
        }
    }
}
