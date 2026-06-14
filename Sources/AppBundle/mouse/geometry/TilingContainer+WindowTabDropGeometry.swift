import AppKit
import Common

extension TilingContainer {
    @MainActor
    var windowTabDropZoneRect: Rect? {
        guard showsWindowTabs, let rect = windowDragVisibleRect else { return nil }
        return rect.tabInsertPreviewRect(barHeight: windowTabBarHeight)
    }

    @MainActor
    var windowTabDropInteractionRect: Rect? {
        guard showsWindowTabs, let rect = windowDragVisibleRect else { return nil }
        return rect.tabInsertInteractionRect(barHeight: windowTabBarHeight)
    }
}

func tabInteractionTopExclusion(_ interactionRect: Rect, in visibleRect: Rect) -> CGFloat {
    max(interactionRect.maxY - visibleRect.minY, 0)
}
