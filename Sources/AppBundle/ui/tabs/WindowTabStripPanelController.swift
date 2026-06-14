import Foundation

@MainActor
final class WindowTabStripPanelController {
    static let shared = WindowTabStripPanelController()

    enum MouseInteractionChromeMode: Equatable {
        case frameOnly
        case hidden
    }

    var visualPanels: [ObjectIdentifier: WindowTabGroupVisualPanel] = [:]
    var stripPanels: [ObjectIdentifier: WindowTabStripPanel] = [:]
    var transientResizeTabGroupId: ObjectIdentifier? = nil
    var transientResizeTabGroupStrip: WindowTabStripViewModel? = nil
    var mouseInteractionChromeMode: MouseInteractionChromeMode? = nil
    var hiddenPassiveTabGroupChromeIds: Set<ObjectIdentifier> = []

    private init() {}
}

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

extension WindowTabStripPanelController {
    @discardableResult
    func updateResizingTabGroupChrome(window: Window, activeWindowRect: Rect) -> Bool {
        guard let transientStrip = resizingTabGroupStrip(window: window, activeWindowRect: activeWindowRect) else {
            transientResizeTabGroupId = nil
            transientResizeTabGroupStrip = nil
            return false
        }

        transientResizeTabGroupId = transientStrip.id
        transientResizeTabGroupStrip = transientStrip
        if hiddenPassiveTabGroupChromeIds.contains(transientStrip.id) {
            orderOutPanels(id: transientStrip.id)
            return true
        }
        visualPanel(for: transientStrip.id).update(with: transientStrip)
        updateInteractivePanelForResizingStrip(transientStrip)
        return true
    }

    func clearTransientResizeChrome() {
        guard transientResizeTabGroupId != nil || transientResizeTabGroupStrip != nil else { return }
        transientResizeTabGroupId = nil
        transientResizeTabGroupStrip = nil
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
              tabGroup.tabActiveWindow == window
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
        transientResizeTabGroupStrip = nil
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
