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
    if container.usesWindowTabBehavior {
        if let activeWindowId, container.containsLeafWindow(withId: activeWindowId) {
            return []
        }
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: max(width, 0), height: max(height, 0))
        guard physicalRect.width > 0, physicalRect.height > 0 else { return [] }
        return [WindowResizePreviewItem(tabGroup: container, rect: physicalRect)]
    }

    guard let mruIndex = container.mostRecentChild?.ownIndex else { return [] }
    var items: [WindowResizePreviewItem] = []
    for (index, child) in container.children.enumerated() {
        let (leadingPadding, trailingPadding) = windowResizePreviewTabPadding(
            index: index,
            count: container.children.count,
            lastIndex: container.children.indices.last,
            mruIndex: mruIndex,
        )
        switch container.orientation {
            case .h:
                items += windowResizePreviewItems(
                    node: child,
                    point: point + CGPoint(x: leadingPadding, y: 0),
                    width: max(width - trailingPadding - leadingPadding, 0),
                    height: height,
                    virtual: virtual,
                    context: context,
                    activeWindowId: activeWindowId,
                )
            case .v:
                items += windowResizePreviewItems(
                    node: child,
                    point: point + CGPoint(x: 0, y: leadingPadding),
                    width: width,
                    height: max(height - leadingPadding - trailingPadding, 0),
                    virtual: virtual,
                    context: context,
                    activeWindowId: activeWindowId,
                )
        }
    }
    return items
}

@MainActor
private func windowResizePreviewTabPadding(
    index: Int,
    count: Int,
    lastIndex: Int?,
    mruIndex: Int,
) -> (leading: CGFloat, trailing: CGFloat) {
    let padding = CGFloat(config.tabGroupPadding)
    return switch index {
        case 0 where count == 1: (0, 0)
        case 0:                  (0, padding)
        case lastIndex:          (padding, 0)
        case mruIndex - 1:       (0, 2 * padding)
        case mruIndex + 1:       (2 * padding, 0)
        default:                 (padding, padding)
    }
}
