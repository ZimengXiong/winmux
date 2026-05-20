import Foundation

extension WindowTabStripPanelController {
    func hideChromeDuringMouseInteraction(showFrameOnly: Bool = true) {
        guard TrayMenuModel.shared.isEnabled, config.windowTabs.enabled else { return }
        let nextMode: MouseInteractionChromeMode = showFrameOnly ? .frameOnly : .hidden
        guard mouseInteractionChromeMode != nextMode || transientResizeTabGroupId != nil else { return }
        mouseInteractionChromeMode = nextMode
        transientResizeTabGroupId = nil
        transientResizeTabGroupStrip = nil
        refresh()
    }

    func showChromeDuringMouseInteraction() {
        guard mouseInteractionChromeMode != nil || !hiddenPassiveTabGroupChromeIds.isEmpty else { return }
        mouseInteractionChromeMode = nil
        hiddenPassiveTabGroupChromeIds.removeAll()
        refresh()
    }

    func refreshHiddenChrome(activeIds: Set<ObjectIdentifier>) {
        for id in Array(visualPanels.keys) {
            orderOutIfVisible(visualPanels[id])
            if !activeIds.contains(id) {
                visualPanels.removeValue(forKey: id)
            }
        }
        for id in Array(stripPanels.keys) {
            orderOutIfVisible(stripPanels[id])
            if !activeIds.contains(id) {
                stripPanels.removeValue(forKey: id)
            }
        }
    }

    @discardableResult
    func clearMouseInteractionChromeSuppressionIfInactive() -> Bool {
        guard currentlyManipulatedWithMouseWindowId == nil,
              mouseInteractionChromeMode != nil
        else { return false }
        mouseInteractionChromeMode = nil
        return true
    }
}
