import Foundation

extension WindowTabStripPanelController {
    func visualPanel(for id: ObjectIdentifier) -> WindowTabGroupVisualPanel {
        let panel = visualPanels[id] ?? WindowTabGroupVisualPanel(id: id)
        visualPanels[id] = panel
        return panel
    }

    func stripPanel(for id: ObjectIdentifier) -> WindowTabStripPanel {
        let panel = stripPanels[id] ?? WindowTabStripPanel(id: id)
        stripPanels[id] = panel
        return panel
    }

    func orderOutPanels(id: ObjectIdentifier) {
        orderOutIfVisible(visualPanels[id])
        orderOutIfVisible(stripPanels[id])
    }

    func removeStalePanels(activeIds: Set<ObjectIdentifier>) {
        removeStaleVisualPanels(activeIds: activeIds)
        removeStaleStripPanels(activeIds: activeIds)
    }

    func removeStaleVisualPanels(activeIds: Set<ObjectIdentifier>) {
        for staleId in visualPanels.keys where !activeIds.contains(staleId) {
            orderOutIfVisible(visualPanels[staleId])
            visualPanels.removeValue(forKey: staleId)
        }
    }

    func removeStaleStripPanels(activeIds: Set<ObjectIdentifier>) {
        for staleId in stripPanels.keys where !activeIds.contains(staleId) {
            orderOutIfVisible(stripPanels[staleId])
            stripPanels.removeValue(forKey: staleId)
        }
    }

    func orderOutIfVisible(_ panel: NSPanelHud?) {
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
    }
}
