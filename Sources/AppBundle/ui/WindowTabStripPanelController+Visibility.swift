import Foundation

extension WindowTabStripPanelController {
    func setHiddenPassiveTabGroupChrome(_ ids: Set<ObjectIdentifier>) {
        guard hiddenPassiveTabGroupChromeIds != ids else { return }
        hiddenPassiveTabGroupChromeIds = ids
        refresh()
    }

    func clearHiddenPassiveTabGroupChrome() {
        guard !hiddenPassiveTabGroupChromeIds.isEmpty else { return }
        hiddenPassiveTabGroupChromeIds.removeAll()
        refresh()
    }

    func hideAll() {
        transientResizeTabGroupId = nil
        mouseInteractionChromeMode = nil
        hiddenPassiveTabGroupChromeIds.removeAll()
        for panel in visualPanels.values {
            panel.orderOut(nil)
        }
        for panel in stripPanels.values {
            panel.orderOut(nil)
        }
        visualPanels.removeAll()
        stripPanels.removeAll()
    }

    func setIgnoresMouseEvents(_ ignoresMouseEvents: Bool) {
        for panel in stripPanels.values {
            panel.setExternalIgnoresMouseEvents(ignoresMouseEvents)
        }
    }
}
