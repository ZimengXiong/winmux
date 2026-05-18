import AppKit
import SwiftUI

extension WindowTabStripView {
    func groupDragGesture(for windowId: UInt32?) -> some Gesture {
        DragGesture(minimumDistance: windowTabStripGroupDragMinimumDistance, coordinateSpace: .global)
            .onChanged { _ in
                noteCurrentMousePointerSample()
                guard let windowId,
                      shouldAllowTabStripChromeGroupDrag(windowId: windowId)
                else { return }
                updateMoveFromTabStrip(windowId)
            }
            .onEnded { _ in
                noteCurrentMousePointerSample()
                guard let windowId,
                      shouldContinueCurrentGroupDrag(windowId: windowId)
                else { return }
                finishMoveFromTabStrip()
            }
    }

    func tabScrollBackgroundGroupDragGesture(
        for windowId: UInt32?,
        context: WindowTabStripLayoutContext,
    ) -> some Gesture {
        DragGesture(minimumDistance: windowTabStripGroupDragMinimumDistance, coordinateSpace: .local)
            .onChanged { value in
                guard isWindowTabStripScrollBackgroundDragStart(
                    localX: value.startLocation.x,
                    contentMinX: tabScrollContentMinX,
                    tabWidth: context.tabWidth,
                    tabCount: strip.tabs.count,
                ) else { return }
                noteCurrentMousePointerSample()
                guard let windowId,
                      shouldAllowTabStripChromeGroupDrag(windowId: windowId)
                else { return }
                updateMoveFromTabStrip(windowId)
            }
            .onEnded { value in
                guard isWindowTabStripScrollBackgroundDragStart(
                    localX: value.startLocation.x,
                    contentMinX: tabScrollContentMinX,
                    tabWidth: context.tabWidth,
                    tabCount: strip.tabs.count,
                ) else { return }
                noteCurrentMousePointerSample()
                guard let windowId,
                      shouldContinueCurrentGroupDrag(windowId: windowId)
                else { return }
                finishMoveFromTabStrip()
            }
    }
}

func isWindowTabStripScrollBackgroundDragStart(
    localX: CGFloat,
    contentMinX: CGFloat,
    tabWidth: CGFloat,
    tabCount: Int,
) -> Bool {
    guard tabCount > 0 else { return true }
    let tabsStart = contentMinX + windowTabStripContentHorizontalPadding
    let tabsWidth = CGFloat(tabCount) * tabWidth
        + CGFloat(max(tabCount - 1, 0)) * windowTabStripTabSpacing
    let tabsEnd = tabsStart + tabsWidth
    return localX < tabsStart || localX > tabsEnd
}
