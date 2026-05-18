import AppKit
import SwiftUI

extension WindowTabStripView {
    func tabDragGesture(
        for tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
    ) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                handleTabDragChanged(tab: tab, translation: value.translation)
            }
            .onEnded { _ in
                handleTabDragEnded(tab: tab, context: context)
            }
    }

    func handleTabDragChanged(tab: WindowTabItemViewModel, translation: CGSize) {
        if shouldPromoteTabStripDragToGroup(windowId: tab.windowId) {
            clearTabDragState()
            updateMoveFromTabStrip(tab.windowId)
            return
        }
        if hasCommittedToDetach {
            updateDetachedTabFromTabStrip(tab.windowId)
            return
        }
        if abs(translation.height) > tabReorderVerticalEscapeThreshold, strip.tabs.count > 1 {
            hasCommittedToDetach = true
            draggingTabId = nil
            hoveredTabId = nil
            dragTranslationX = 0
            updateDetachedTabFromTabStrip(tab.windowId)
            return
        }
        draggingTabId = tab.windowId
        hoveredTabId = nil
        dragTranslationX = translation.width
    }

    func handleTabDragEnded(tab: WindowTabItemViewModel, context: WindowTabStripLayoutContext) {
        if shouldContinueCurrentGroupDrag(windowId: tab.windowId) {
            finishMoveFromTabStrip()
        } else if hasCommittedToDetach {
            hasCommittedToDetach = false
            Task { @MainActor in
                try? await resetManipulatedWithMouseIfPossible()
            }
        } else if let srcIdx = draggingIndex(context: context),
                  let tgtIdx = reorderTargetIndex(context: context),
                  srcIdx != tgtIdx {
            settleReorderedTab(
                windowId: tab.windowId,
                sourceIndex: srcIdx,
                targetIndex: tgtIdx,
                orderBeforeDrop: context.tabOrder,
            )
            reorderTabInStrip(tab.windowId, toIndex: tgtIdx)
            return
        }
        clearTabDragState()
    }

    func clearTabDragState() {
        draggingTabId = nil
        hoveredTabId = nil
        dragTranslationX = 0
        hasCommittedToDetach = false
    }
}
