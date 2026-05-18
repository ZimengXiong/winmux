import AppKit

func workspaceSidebarCursorPreviewRect(
    at mouseLocation: CGPoint,
    sidebarRect: Rect,
    width: CGFloat,
    height: CGFloat,
) -> Rect {
    let horizontalInset: CGFloat = 10
    let verticalInset: CGFloat = 8
    let availableWidth = min(width, max(sidebarRect.width - horizontalInset * 2, 0))
    let clampedX = max(
        sidebarRect.minX + horizontalInset,
        min(mouseLocation.x - (availableWidth / 2), sidebarRect.maxX - availableWidth - horizontalInset),
    )
    let clampedY = max(
        sidebarRect.minY + verticalInset,
        min(mouseLocation.y - (height / 2), sidebarRect.maxY - height - verticalInset),
    )
    return Rect(topLeftX: clampedX, topLeftY: clampedY, width: availableWidth, height: height)
}
