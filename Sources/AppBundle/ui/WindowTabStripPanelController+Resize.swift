import Foundation

extension WindowTabStripPanelController {
    @discardableResult
    func updateResizingTabGroupChrome(window: Window, activeWindowRect: Rect) -> Bool {
        guard !windowResizeUsesActiveTabGroupChrome(window: window) else {
            transientResizeTabGroupId = nil
            return false
        }
        guard let transientStrip = resizingTabGroupStrip(window: window, activeWindowRect: activeWindowRect) else {
            transientResizeTabGroupId = nil
            return false
        }

        transientResizeTabGroupId = transientStrip.id
        if hiddenPassiveTabGroupChromeIds.contains(transientStrip.id) {
            orderOutPanels(id: transientStrip.id)
            return true
        }
        visualPanel(for: transientStrip.id).update(with: transientStrip)
        updateInteractivePanelForResizingStrip(transientStrip)
        return true
    }

    func clearTransientResizeChrome() {
        guard transientResizeTabGroupId != nil else { return }
        transientResizeTabGroupId = nil
    }

    func updateInteractivePanelForResizingStrip(_ strip: WindowTabStripViewModel) {
        if mouseInteractionChromeMode != nil {
            orderOutIfVisible(stripPanels[strip.id])
        } else {
            stripPanel(for: strip.id).update(with: strip)
        }
    }

    func resizingTabGroupStrip(window: Window, activeWindowRect: Rect) -> WindowTabStripViewModel? {
        guard TrayMenuModel.shared.isEnabled,
              config.windowTabs.enabled,
              let tabGroup = window.nearestWindowTabGroup,
              tabGroup.usesWindowTabBehavior,
              tabGroup.tabActiveWindow != window
        else { return nil }
        let id = ObjectIdentifier(tabGroup)
        guard let baseStrip = TrayMenuModel.shared.windowTabStrips.first(where: { $0.id == id }) else { return nil }
        return resizingTabGroupStrip(baseStrip: baseStrip, activeWindowRect: activeWindowRect)
    }

    func resizingTabGroupStrip(baseStrip: WindowTabStripViewModel, activeWindowRect: Rect) -> WindowTabStripViewModel {
        let groupFrameRect = windowTabGroupFrameRect(forActiveWindowContentRect: activeWindowRect)
        let tabBarRect = windowTabBarRect(forGroupFrameRect: groupFrameRect)
        return WindowTabStripViewModel(
            id: baseStrip.id,
            workspaceName: baseStrip.workspaceName,
            frame: tabBarRect.toAppKitScreenRect.alignedToBackingPixels(),
            groupFrame: groupFrameRect.toAppKitScreenRect.alignedToBackingPixels(),
            activeWindowId: baseStrip.activeWindowId,
            activeWindowCornerRadius: baseStrip.activeWindowCornerRadius,
            tabs: baseStrip.tabs,
            occludingFloatingWindowFrames: baseStrip.occludingFloatingWindowFrames,
        )
    }
}
