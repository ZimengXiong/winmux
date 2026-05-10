import AppKit
import Common
import SwiftUI

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
    var mouseInteractionChromeMode: MouseInteractionChromeMode? = nil
    var hiddenPassiveTabGroupChromeIds: Set<ObjectIdentifier> = []

    private init() {}

    func refresh() {
        if transientResizeTabGroupId != nil {
            transientResizeTabGroupId = nil
        }
        guard TrayMenuModel.shared.isEnabled, config.windowTabs.enabled else {
            hideAll()
            return
        }

        let strips = TrayMenuModel.shared.windowTabStrips
        let activeIds = Set(strips.map(\.id))
        if let mouseInteractionChromeMode {
            switch mouseInteractionChromeMode {
                case .frameOnly:
                    refreshFrameOnlyChrome(strips: strips, activeIds: activeIds)
                case .hidden:
                    refreshHiddenChrome(activeIds: activeIds)
            }
            return
        }
        for strip in strips {
            if hiddenPassiveTabGroupChromeIds.contains(strip.id) {
                orderOutPanels(id: strip.id)
                continue
            }
            let visualPanel = visualPanels[strip.id] ?? WindowTabGroupVisualPanel(id: strip.id)
            visualPanels[strip.id] = visualPanel
            visualPanel.update(with: strip, drawsMockTabs: false)

            let stripPanel = stripPanels[strip.id] ?? WindowTabStripPanel(id: strip.id)
            stripPanels[strip.id] = stripPanel
            stripPanel.update(with: strip)
        }
        for staleId in visualPanels.keys where !activeIds.contains(staleId) {
            visualPanels[staleId]?.orderOut(nil)
            visualPanels.removeValue(forKey: staleId)
        }
        for staleId in stripPanels.keys where !activeIds.contains(staleId) {
            stripPanels[staleId]?.orderOut(nil)
            stripPanels.removeValue(forKey: staleId)
        }
    }

    @discardableResult
    func updateResizingTabGroupChrome(window: Window, activeWindowRect: Rect) -> Bool {
        guard TrayMenuModel.shared.isEnabled,
              config.windowTabs.enabled,
              let tabGroup = window.nearestWindowTabGroup,
              tabGroup.usesWindowTabBehavior,
              tabGroup.tabActiveWindow == window
        else {
            transientResizeTabGroupId = nil
            return false
        }
        let id = ObjectIdentifier(tabGroup)
        guard let baseStrip = TrayMenuModel.shared.windowTabStrips.first(where: { $0.id == id }) else {
            transientResizeTabGroupId = nil
            return false
        }

        let groupFrameRect = windowTabGroupFrameRect(forActiveWindowContentRect: activeWindowRect)
        let tabBarRect = windowTabBarRect(forGroupFrameRect: groupFrameRect)
        let transientStrip = WindowTabStripViewModel(
            id: baseStrip.id,
            workspaceName: baseStrip.workspaceName,
            frame: tabBarRect.toAppKitScreenRect.alignedToBackingPixels(),
            groupFrame: groupFrameRect.toAppKitScreenRect.alignedToBackingPixels(),
            activeWindowId: baseStrip.activeWindowId,
            activeWindowCornerRadius: baseStrip.activeWindowCornerRadius,
            tabs: baseStrip.tabs,
            occludingFloatingWindowFrames: baseStrip.occludingFloatingWindowFrames,
        )

        transientResizeTabGroupId = id
        let visualPanel = visualPanels[id] ?? WindowTabGroupVisualPanel(id: id)
        visualPanels[id] = visualPanel
        if hiddenPassiveTabGroupChromeIds.contains(id) {
            orderOutPanels(id: id)
            return true
        }
        visualPanel.update(with: transientStrip, drawsMockTabs: mouseInteractionChromeMode == .frameOnly)

        if mouseInteractionChromeMode != nil {
            stripPanels[id]?.orderOut(nil)
        } else {
            let stripPanel = stripPanels[id] ?? WindowTabStripPanel(id: id)
            stripPanels[id] = stripPanel
            stripPanel.update(with: transientStrip)
        }
        return true
    }

    func clearTransientResizeChrome() {
        guard transientResizeTabGroupId != nil else { return }
        transientResizeTabGroupId = nil
    }

    func hideChromeDuringMouseInteraction(showFrameOnly: Bool = true) {
        guard TrayMenuModel.shared.isEnabled, config.windowTabs.enabled else { return }
        let nextMode: MouseInteractionChromeMode = showFrameOnly ? .frameOnly : .hidden
        guard mouseInteractionChromeMode != nextMode || transientResizeTabGroupId != nil else { return }
        mouseInteractionChromeMode = nextMode
        transientResizeTabGroupId = nil
        refresh()
    }

    func showChromeDuringMouseInteraction() {
        guard mouseInteractionChromeMode != nil || transientResizeTabGroupId != nil else { return }
        mouseInteractionChromeMode = nil
        transientResizeTabGroupId = nil
        hiddenPassiveTabGroupChromeIds.removeAll()
        refresh()
    }

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

    @discardableResult
    func clearMouseInteractionChromeSuppressionIfInactive() -> Bool {
        guard currentlyManipulatedWithMouseWindowId == nil,
              mouseInteractionChromeMode != nil
        else { return false }
        mouseInteractionChromeMode = nil
        return true
    }

    func hideAll() {
        if transientResizeTabGroupId != nil {
            transientResizeTabGroupId = nil
        }
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

    func orderOutPanels(id: ObjectIdentifier) {
        visualPanels[id]?.orderOut(nil)
        stripPanels[id]?.orderOut(nil)
    }

    func refreshFrameOnlyChrome(strips: [WindowTabStripViewModel], activeIds: Set<ObjectIdentifier>) {
        for strip in strips {
            if hiddenPassiveTabGroupChromeIds.contains(strip.id) {
                orderOutPanels(id: strip.id)
                continue
            }
            let visualPanel = visualPanels[strip.id] ?? WindowTabGroupVisualPanel(id: strip.id)
            visualPanels[strip.id] = visualPanel
            visualPanel.update(with: strip, drawsMockTabs: true)
            stripPanels[strip.id]?.orderOut(nil)
        }
        for staleId in visualPanels.keys where !activeIds.contains(staleId) {
            visualPanels[staleId]?.orderOut(nil)
            visualPanels.removeValue(forKey: staleId)
        }
        for staleId in stripPanels.keys where !activeIds.contains(staleId) {
            stripPanels[staleId]?.orderOut(nil)
            stripPanels.removeValue(forKey: staleId)
        }
    }

    func refreshHiddenChrome(activeIds: Set<ObjectIdentifier>) {
        for id in Array(visualPanels.keys) {
            visualPanels[id]?.orderOut(nil)
            if !activeIds.contains(id) {
                visualPanels.removeValue(forKey: id)
            }
        }
        for id in Array(stripPanels.keys) {
            stripPanels[id]?.orderOut(nil)
            if !activeIds.contains(id) {
                stripPanels.removeValue(forKey: id)
            }
        }
    }
}

@MainActor
final class WindowTabGroupVisualPanel: NSPanelHud {
    let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    var currentContent: WindowTabGroupChromeContent? = nil
    var currentPanelFrame: CGRect? = nil

    init(id: ObjectIdentifier) {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowTabVisualPanelPrefix + String(id.hashValue))
        hasShadow = false
        isFloatingPanel = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = .clear
        ignoresMouseEvents = true
        applyWinMuxLayer(.windowChrome)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(with strip: WindowTabStripViewModel, drawsMockTabs: Bool) {
        let displayStrip = strip.alignedForWindowTabChrome()
        let panelFrame = displayStrip.groupFrame
        let nextContent = WindowTabGroupChromeContent(strip: displayStrip, drawsMockTabs: drawsMockTabs)
        let contentChanged = currentContent != nextContent
        let frameChanged = currentPanelFrame != panelFrame
        if !contentChanged, !frameChanged, isVisible {
            ignoresMouseEvents = true
            return
        }
        if contentChanged {
            hostingView.rootView = AnyView(WindowTabGroupVisualView(
                strip: displayStrip,
                drawsMockTabs: drawsMockTabs,
            ))
            currentContent = nextContent
        }
        currentPanelFrame = panelFrame
        debugFocusLog("WindowTabGroupVisualPanel.update id=\(String(describing: identifier?.rawValue)) frame=\(panelFrame)")
        setWindowTabChromePanelFrame(panelFrame, on: self)
        ignoresMouseEvents = true
        applyWindowTabVisualStackingPolicy(for: displayStrip, to: self)
    }
}

@MainActor
final class WindowTabStripPanel: NSPanelHud {
    let hostingView = WindowTabStripHostingView(rootView: AnyView(EmptyView()))
    var currentContent: WindowTabGroupChromeContent? = nil
    var currentPanelFrame: CGRect? = nil
    var externallyIgnoresMouseEvents = false
    var tabStripIsOccludedByFloatingWindow = false

    init(id: ObjectIdentifier) {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowTabStripPanelPrefix + String(id.hashValue))
        hasShadow = false
        isFloatingPanel = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = .clear
        applyWinMuxLayer(.windowChrome)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func update(with strip: WindowTabStripViewModel) {
        let displayStrip = strip.alignedForWindowTabChrome()
        let tabFrame = displayStrip.frame
        let nextContent = WindowTabGroupChromeContent(strip: displayStrip)
        let contentChanged = currentContent != nextContent
        let frameChanged = currentPanelFrame != tabFrame
        let nextOccluded = displayStrip.tabStripIsOccludedByFloatingWindow
        if !contentChanged, !frameChanged, tabStripIsOccludedByFloatingWindow == nextOccluded, isVisible {
            updateMousePolicy()
            return
        }
        if contentChanged {
            hostingView.rootView = AnyView(WindowTabStripView(strip: displayStrip, drawsChrome: false))
            currentContent = nextContent
        }
        currentPanelFrame = tabFrame
        debugFocusLog("WindowTabStripPanel.update id=\(String(describing: identifier?.rawValue)) frame=\(tabFrame)")
        setWindowTabChromePanelFrame(tabFrame, on: self)
        tabStripIsOccludedByFloatingWindow = nextOccluded
        updateMousePolicy()
        applyWindowTabStripStackingPolicy(for: displayStrip, to: self)
    }

    func setExternalIgnoresMouseEvents(_ ignoresMouseEvents: Bool) {
        externallyIgnoresMouseEvents = ignoresMouseEvents
        updateMousePolicy()
    }

    func updateMousePolicy() {
        let disabled = externallyIgnoresMouseEvents ||
            currentlyManipulatedWithMouseWindowId != nil ||
            tabStripIsOccludedByFloatingWindow
        ignoresMouseEvents = disabled
    }
}

final class WindowTabStripHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

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
    let previousLevel = panel.level
    let previousIsFloating = panel.isFloatingPanel
    let targetLevel = WinMuxPanelLayer.windowChrome.level

    panel.isFloatingPanel = false
    panel.level = targetLevel
    if let activeWindowId = strip.activeWindowId {
        panel.order(.below, relativeTo: Int(activeWindowId))
    } else if !panel.isVisible || previousLevel != targetLevel || previousIsFloating {
        panel.orderFrontRegardless()
    }
}

@MainActor
func applyWindowTabStripStackingPolicy(for strip: WindowTabStripViewModel, to panel: NSPanelHud) {
    let previousLevel = panel.level
    let previousIsFloating = panel.isFloatingPanel
    let targetLevel = WinMuxPanelLayer.windowChrome.level

    panel.isFloatingPanel = false
    panel.level = targetLevel
    if let activeWindowId = strip.activeWindowId {
        panel.order(.above, relativeTo: Int(activeWindowId))
    } else if !panel.isVisible || previousLevel != targetLevel || previousIsFloating {
        panel.orderFrontRegardless()
    }
}

struct WindowTabGroupChromeContent: Equatable {
    let workspaceName: String
    let activeWindowId: UInt32?
    let activeWindowCornerRadius: CGFloat
    let tabs: [WindowTabItemViewModel]
    let occludingFloatingWindowFrames: [CGRect]
    let drawsMockTabs: Bool

    init(strip: WindowTabStripViewModel, drawsMockTabs: Bool = false) {
        workspaceName = strip.workspaceName
        activeWindowId = strip.activeWindowId
        activeWindowCornerRadius = strip.activeWindowCornerRadius
        tabs = strip.tabs
        occludingFloatingWindowFrames = strip.occludingFloatingWindowFrames
        self.drawsMockTabs = drawsMockTabs
    }
}

