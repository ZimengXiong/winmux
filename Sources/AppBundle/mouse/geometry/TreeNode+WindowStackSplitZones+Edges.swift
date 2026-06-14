import Common

extension TreeNode {
    func leftStackSplitDropZone(sideBodyRect: Rect, swapRect: Rect) -> Rect? {
        guard swapRect.minX > sideBodyRect.minX else { return nil }
        return Rect(
            topLeftX: sideBodyRect.topLeftX,
            topLeftY: sideBodyRect.topLeftY,
            width: swapRect.minX - sideBodyRect.minX,
            height: sideBodyRect.height,
        )
    }

    func rightStackSplitDropZone(sideBodyRect: Rect, swapRect: Rect) -> Rect? {
        guard sideBodyRect.maxX > swapRect.maxX else { return nil }
        return Rect(
            topLeftX: swapRect.maxX,
            topLeftY: sideBodyRect.topLeftY,
            width: sideBodyRect.maxX - swapRect.maxX,
            height: sideBodyRect.height,
        )
    }

    func aboveStackSplitDropZone(centeredBodyRect: Rect, swapRect: Rect) -> Rect? {
        guard swapRect.minY > centeredBodyRect.minY else { return nil }
        return Rect(
            topLeftX: swapRect.topLeftX,
            topLeftY: centeredBodyRect.topLeftY,
            width: swapRect.width,
            height: swapRect.minY - centeredBodyRect.minY,
        )
    }

    func belowStackSplitDropZone(centeredBodyRect: Rect, swapRect: Rect) -> Rect? {
        guard centeredBodyRect.maxY > swapRect.maxY else { return nil }
        return Rect(
            topLeftX: swapRect.topLeftX,
            topLeftY: swapRect.maxY,
            width: swapRect.width,
            height: centeredBodyRect.maxY - swapRect.maxY,
        )
    }
}
