import Foundation

extension WindowTabStripView {
    func settleReorderedTab(
        windowId: UInt32,
        sourceIndex: Int,
        targetIndex: Int,
        orderBeforeDrop: [UInt32],
    ) {
        pendingReorderDrop = WindowTabPendingReorderDrop(
            windowId: windowId,
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            orderBeforeDrop: orderBeforeDrop,
        )
        draggingTabId = nil
        hoveredTabId = nil
        dragTranslationX = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + windowTabReorderDropClearDelay) {
            guard pendingReorderDrop?.windowId == windowId else { return }
            pendingReorderDrop = nil
        }
    }

    func clearPendingReorderDropIfModelApplied(currentOrder: [UInt32]) {
        guard let pendingReorderDrop else { return }
        guard pendingReorderDrop.orderBeforeDrop != currentOrder else { return }
        self.pendingReorderDrop = nil
    }

    func updateHoveredTab(_ windowId: UInt32, hovering: Bool) {
        guard draggingTabId == nil, !hasCommittedToDetach else {
            hoveredTabId = nil
            return
        }
        if hovering {
            hoveredTabId = windowId
        } else if hoveredTabId == windowId {
            hoveredTabId = nil
        }
    }
}
