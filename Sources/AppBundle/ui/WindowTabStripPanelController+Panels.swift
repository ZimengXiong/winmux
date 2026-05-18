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
        visualPanels[id]?.orderOut(nil)
        stripPanels[id]?.orderOut(nil)
    }

    func removeStalePanels(activeIds: Set<ObjectIdentifier>) {
        removeStaleVisualPanels(activeIds: activeIds)
        removeStaleStripPanels(activeIds: activeIds)
    }

    func removeStaleVisualPanels(activeIds: Set<ObjectIdentifier>) {
        for staleId in visualPanels.keys where !activeIds.contains(staleId) {
            visualPanels[staleId]?.orderOut(nil)
            visualPanels.removeValue(forKey: staleId)
        }
    }

    func removeStaleStripPanels(activeIds: Set<ObjectIdentifier>) {
        for staleId in stripPanels.keys where !activeIds.contains(staleId) {
            stripPanels[staleId]?.orderOut(nil)
            stripPanels.removeValue(forKey: staleId)
        }
    }
}
