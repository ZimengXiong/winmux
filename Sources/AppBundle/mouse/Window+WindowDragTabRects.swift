import Common

extension Window {
    @MainActor
    var tabStackTargetRects: (containerRect: Rect, previewRect: Rect, interactionRect: Rect)? {
        if let parent = parent as? TilingContainer,
           parent.layout == .tabGroup,
           let previewRect = parent.windowTabDropZoneRect,
           let interactionRect = parent.windowTabDropInteractionRect
        {
            return (
                containerRect: parent.windowDragVisibleRect ?? previewRect,
                previewRect: previewRect,
                interactionRect: interactionRect,
            )
        }
        guard let previewRect = tabDropZoneRect,
              let interactionRect = tabDropInteractionRect
        else { return nil }
        return (
            containerRect: windowDragVisibleRect ?? previewRect,
            previewRect: previewRect,
            interactionRect: interactionRect,
        )
    }

    @MainActor
    var tabDropZoneRect: Rect? {
        guard let rect = windowDragVisibleRect else { return nil }
        return rect.tabInsertPreviewRect(barHeight: resolvedWindowTabBarHeight())
    }

    @MainActor
    var tabDropInteractionRect: Rect? {
        guard let rect = windowDragVisibleRect else { return nil }
        return rect.tabInsertInteractionRect(barHeight: resolvedWindowTabBarHeight())
    }

    @MainActor
    var tabDetachPreviewRect: Rect? {
        if let parent = parent as? TilingContainer,
           parent.layout == .tabGroup,
           let rect = parent.lastAppliedLayoutPhysicalRect
        {
            return rect
        }
        return lastAppliedLayoutPhysicalRect
    }

    @MainActor
    func tabDetachKeepRect(origin: TabDetachOrigin) -> Rect? {
        guard let parent = parent as? TilingContainer, parent.layout == .tabGroup else { return nil }
        return switch origin {
            case .window:
                lastAppliedLayoutPhysicalRect?.expanded(left: 8, right: 8, top: 8, bottom: 12)
                    ?? parent.lastAppliedLayoutPhysicalRect?.insetBy(left: 24, right: 24, top: 14, bottom: 18)
            case .tabStrip:
                (parent.windowTabDropZoneRect ?? parent.windowTabBarRect)?.expanded(left: 4, right: 4, top: 4, bottom: 6)
        }
    }
}
