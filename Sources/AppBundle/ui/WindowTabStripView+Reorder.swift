import SwiftUI

extension WindowTabStripView {
    func tabVisualOffset(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
    ) -> CGFloat {
        if let reentryPreview = trayModel.windowTabReentryPreview,
           reentryPreview.stripId == strip.id,
           reentryPreview.orderBeforeDrop == context.tabOrder {
            return tabReentryVisualOffset(for: tab, context: context, drop: reentryPreview)
        }
        if let pendingReorderDrop, pendingReorderDrop.orderBeforeDrop == context.tabOrder {
            return pendingReorderOffset(for: tab, context: context, drop: pendingReorderDrop)
        }
        guard let draggingIndex = draggingIndex(context: context),
              let targetIndex = reorderTargetIndex(context: context)
        else {
            return tab.windowId == draggingTabId ? dragTranslationX : 0
        }
        if tab.windowId == draggingTabId {
            return dragTranslationX
        }
        return tabShiftOffset(
            for: tab,
            context: context,
            sourceIndex: draggingIndex,
            targetIndex: targetIndex,
        )
    }

    func draggingIndex(context: WindowTabStripLayoutContext) -> Int? {
        draggingTabId.flatMap { context.tabIndicesById[$0] }
    }

    func reorderTargetIndex(context: WindowTabStripLayoutContext) -> Int? {
        draggingIndex(context: context).map { sourceIndex in
            let delta = Int(round(dragTranslationX / context.effectiveTabWidth))
            return max(0, min(sourceIndex + delta, strip.tabs.count - 1))
        }
    }

    func pendingReorderOffset(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        drop: WindowTabPendingReorderDrop,
    ) -> CGFloat {
        if tab.windowId == drop.windowId {
            if let sourceVisualOffset = drop.sourceVisualOffset {
                return sourceVisualOffset
            }
            return CGFloat(drop.targetIndex - drop.sourceIndex) * context.effectiveTabWidth
        }
        return tabShiftOffset(
            for: tab,
            context: context,
            sourceIndex: drop.sourceIndex,
            targetIndex: drop.targetIndex,
        )
    }

    func tabReentryVisualOffset(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        drop: WindowTabPendingReorderDrop,
    ) -> CGFloat {
        if tab.windowId == drop.windowId {
            return drop.sourceVisualOffset ?? CGFloat(drop.targetIndex - drop.sourceIndex) * context.effectiveTabWidth
        }
        return tabShiftOffset(
            for: tab,
            context: context,
            sourceIndex: drop.sourceIndex,
            targetIndex: drop.targetIndex,
        )
    }

    func tabShiftOffset(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        sourceIndex: Int,
        targetIndex: Int,
    ) -> CGFloat {
        guard let tabIndex = context.tabIndicesById[tab.windowId] else { return 0 }
        if sourceIndex < targetIndex, tabIndex > sourceIndex, tabIndex <= targetIndex {
            return -context.effectiveTabWidth
        }
        if sourceIndex > targetIndex, tabIndex >= targetIndex, tabIndex < sourceIndex {
            return context.effectiveTabWidth
        }
        return 0
    }

}
