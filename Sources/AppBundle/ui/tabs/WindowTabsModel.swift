import AppKit

@MainActor
func updateWindowTabModel() async {
    let didClearMouseInteractionChromeSuppression =
        WindowTabStripPanelController.shared.clearMouseInteractionChromeSuppressionIfInactive()
    guard TrayMenuModel.shared.isEnabled, config.windowTabs.enabled else {
        TrayMenuModel.shared.setIfChanged(\.windowTabStrips, [])
        WindowTabStripPanelController.shared.refresh()
        debugFocusLog("updateWindowTabModel disabled -> cleared")
        return
    }
    pruneCachedWindowTitles()

    let strips = await buildWindowTabStripViewModelsFromChromeItems()

    if TrayMenuModel.shared.windowTabStrips != strips {
        debugFocusLog("updateWindowTabModel apply strips old=\(TrayMenuModel.shared.windowTabStrips.map(\.frame)) new=\(strips.map(\.frame))")
        TrayMenuModel.shared.windowTabStrips = strips
        WindowTabStripPanelController.shared.refresh()
    } else {
        if didClearMouseInteractionChromeSuppression {
            WindowTabStripPanelController.shared.refresh()
        }
        debugFocusLog("updateWindowTabModel unchanged strips=\(strips.map(\.frame))")
    }
}
