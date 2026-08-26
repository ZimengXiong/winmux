import AppKit
import Common

@MainActor
func windowResizePreviewTabGroupItems(
    container: TilingContainer,
    point: CGPoint,
    width: CGFloat,
    height: CGFloat,
    virtual: Rect,
    context: WindowResizePreviewLayoutContext,
    activeWindowId: UInt32?,
) -> [WindowResizePreviewItem] {
    if let activeWindowId, container.containsLeafWindow(withId: activeWindowId) {
        return []
    }
    let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: max(width, 0), height: max(height, 0))
    guard physicalRect.width > 0, physicalRect.height > 0 else { return [] }
    // A resize preview treats every tab group as one surface. Its individual tabs are not
    // independently resized, and drawing them separately creates a misleading split preview.
    return [WindowResizePreviewItem(
        tabGroup: container,
        rect: windowResizePreviewRenderedTabGroupRect(container, proposedGroupRect: physicalRect),
    )]
}
