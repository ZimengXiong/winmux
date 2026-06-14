import AppKit
import Common

extension WindowTabStripViewModel {
    func alignedForWindowTabChrome() -> WindowTabStripViewModel {
        WindowTabStripViewModel(
            id: id,
            workspaceName: workspaceName,
            frame: frame.alignedToBackingPixels(),
            groupFrame: groupFrame.alignedToBackingPixels(),
            activeWindowId: activeWindowId,
            activeWindowCornerRadius: activeWindowCornerRadius,
            tabs: tabs,
            occludingFloatingWindowFrames: occludingFloatingWindowFrames,
        )
    }
}

@MainActor
func setWindowTabChromePanelFrame(_ frame: CGRect, on panel: NSPanelHud) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    panel.setFrame(frame, display: true, animate: false)
    panel.contentView?.layoutSubtreeIfNeeded()
    CATransaction.commit()
}

@MainActor
func applyWindowTabVisualStackingPolicy(for strip: WindowTabStripViewModel, to panel: NSPanelHud) {
    applyWindowTabChromeStackingPolicy(for: strip, to: panel, order: .below)
}

@MainActor
func applyWindowTabStripStackingPolicy(for strip: WindowTabStripViewModel, to panel: NSPanelHud) {
    applyWindowTabChromeStackingPolicy(for: strip, to: panel, order: .above)
}

@MainActor
private func applyWindowTabChromeStackingPolicy(
    for strip: WindowTabStripViewModel,
    to panel: NSPanelHud,
    order: NSWindow.OrderingMode,
) {
    let previousLevel = panel.level
    let previousIsFloating = panel.isFloatingPanel
    let targetLevel = WinMuxPanelLayer.windowChrome.level

    panel.isFloatingPanel = false
    panel.level = targetLevel
    if let activeWindowId = strip.activeWindowId {
        panel.order(order, relativeTo: Int(activeWindowId))
    } else if !panel.isVisible || previousLevel != targetLevel || previousIsFloating {
        panel.orderFrontRegardless()
    }
}
