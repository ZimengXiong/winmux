import Foundation

extension WindowTabStripPanelController {
    func refresh() {
        guard TrayMenuModel.shared.isEnabled, config.windowTabs.enabled else {
            hideAll()
            return
        }

        let strips = windowTabStripsWithTransientResizeApplied(TrayMenuModel.shared.windowTabStrips)
        let activeIds = Set(strips.map(\.id))
        if let mouseInteractionChromeMode {
            refreshSuppressedChrome(mode: mouseInteractionChromeMode, strips: strips, activeIds: activeIds)
            return
        }
        refreshInteractiveChrome(strips: strips, activeIds: activeIds)
    }

    func windowTabStripsWithTransientResizeApplied(_ strips: [WindowTabStripViewModel]) -> [WindowTabStripViewModel] {
        guard let transientResizeTabGroupStrip else { return strips }
        return strips.map { strip in
            strip.id == transientResizeTabGroupStrip.id ? transientResizeTabGroupStrip : strip
        }
    }

    func refreshInteractiveChrome(strips: [WindowTabStripViewModel], activeIds: Set<ObjectIdentifier>) {
        for strip in strips {
            guard !hiddenPassiveTabGroupChromeIds.contains(strip.id) else {
                orderOutPanels(id: strip.id)
                continue
            }
            visualPanel(for: strip.id).update(with: strip)
            stripPanel(for: strip.id).update(with: strip)
        }
        removeStalePanels(activeIds: activeIds)
    }

    func refreshSuppressedChrome(
        mode: MouseInteractionChromeMode,
        strips: [WindowTabStripViewModel],
        activeIds: Set<ObjectIdentifier>,
    ) {
        switch mode {
            case .frameOnly:
                refreshFrameOnlyChrome(strips: strips, activeIds: activeIds)
            case .hidden:
                refreshHiddenChrome(activeIds: activeIds)
        }
    }

    func refreshFrameOnlyChrome(strips: [WindowTabStripViewModel], activeIds: Set<ObjectIdentifier>) {
        for strip in strips {
            guard !hiddenPassiveTabGroupChromeIds.contains(strip.id) else {
                orderOutPanels(id: strip.id)
                continue
            }
            visualPanel(for: strip.id).update(with: strip)
            orderOutIfVisible(stripPanels[strip.id])
        }
        removeStalePanels(activeIds: activeIds)
    }
}
