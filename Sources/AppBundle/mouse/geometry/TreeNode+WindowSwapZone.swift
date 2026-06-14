import Common

extension TreeNode {
    @MainActor
    var swapDropZoneRect: Rect? {
        guard let bodyRect = centeredBodyDropZoneRect else { return nil }
        let swapWidth = min(bodyRect.width, max(bodyRect.width * 0.2, 28))
        let swapHeight = min(bodyRect.height, max(bodyRect.height * 0.2, 28))
        let swapRect = Rect(
            topLeftX: bodyRect.topLeftX + (bodyRect.width - swapWidth) / 2,
            topLeftY: bodyRect.topLeftY + (bodyRect.height - swapHeight) / 2,
            width: swapWidth,
            height: swapHeight,
        )
        guard swapRect.width > 0, swapRect.height > 0 else { return nil }
        return swapRect
    }
}
