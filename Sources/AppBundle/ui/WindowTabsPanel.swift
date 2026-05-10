import AppKit
import SwiftUI

private let windowTabVisualPanelPrefix = "WinMux.windowTabs.visual."
private let windowTabStripPanelPrefix = "WinMux.windowTabs.strip."
private let windowTabDropPreviewPanelId = "WinMux.windowTabs.dropPreview"
private let windowDragCursorProxyPanelId = "WinMux.windowTabs.cursorProxy"
private let windowPreviewCornerAlphaThreshold: CGFloat = 0.3
private let windowPreviewCornerScanLimit = 48
private let windowTabReorderDropClearDelay: TimeInterval = 0.24

@MainActor
var windowPreviewCornerRadiusCache: [UInt32: CGFloat] = [:]

@MainActor
func estimatedWindowPreviewCornerRadius(for windowId: UInt32) -> CGFloat {
    if let cached = windowPreviewCornerRadiusCache[windowId] {
        return cached
    }
    guard CGPreflightScreenCaptureAccess(),
          let resolvedRadius = estimateWindowPreviewCornerRadiusFromImage(windowId: windowId)
    else {
        return windowTabPreviewCornerRadius
    }
    windowPreviewCornerRadiusCache[windowId] = resolvedRadius
    return resolvedRadius
}

private func estimateWindowPreviewCornerRadiusFromImage(windowId: UInt32) -> CGFloat? {
    guard let cgImage = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(windowId),
        [.boundsIgnoreFraming, .nominalResolution],
    ) else {
        return nil
    }
    return estimateTopCornerRadius(in: cgImage)
}

private func estimateTopCornerRadius(in image: CGImage) -> CGFloat? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    let width = bitmap.pixelsWide
    let height = bitmap.pixelsHigh
    let maxScan = min(windowPreviewCornerScanLimit, width / 2, height / 2)
    guard maxScan > 0 else { return nil }

    func alphaAt(x: Int, yFromTop: Int) -> CGFloat {
        let bitmapY = height - 1 - yFromTop
        guard bitmapY >= 0,
              bitmapY < height,
              x >= 0,
              x < width
        else {
            return 0
        }
        return bitmap.colorAt(x: x, y: bitmapY)?.alphaComponent ?? 0
    }

    var samples: [Int] = []

    // Scan horizontal insets at multiple rows from top (both edges)
    for row in 0 ..< min(4, maxScan) {
        for step in 0 ..< maxScan {
            if alphaAt(x: step, yFromTop: row) > windowPreviewCornerAlphaThreshold {
                samples.append(step)
                break
            }
        }
        for step in 0 ..< maxScan {
            if alphaAt(x: width - 1 - step, yFromTop: row) > windowPreviewCornerAlphaThreshold {
                samples.append(step)
                break
            }
        }
    }

    // Scan vertical insets at leftmost and rightmost columns from top
    for x in [0, width - 1] {
        for step in 0 ..< maxScan {
            if alphaAt(x: x, yFromTop: step) > windowPreviewCornerAlphaThreshold {
                samples.append(step)
                break
            }
        }
    }

    guard samples.count >= 6 else { return nil }

    let sorted = samples.sorted()
    let median = sorted[sorted.count / 2]

    let consistent = samples.filter { abs($0 - median) <= 2 }
    guard Double(consistent.count) >= Double(samples.count) * 0.6 else {
        return nil
    }

    guard median >= 4 else { return nil }
    return CGFloat(median)
}

@MainActor
final class WindowTabStripPanelController {
    static let shared = WindowTabStripPanelController()

    private enum MouseInteractionChromeMode: Equatable {
        case frameOnly
        case hidden
    }

    private var visualPanels: [ObjectIdentifier: WindowTabGroupVisualPanel] = [:]
    private var stripPanels: [ObjectIdentifier: WindowTabStripPanel] = [:]
    private var transientResizeTabGroupId: ObjectIdentifier? = nil
    private var mouseInteractionChromeMode: MouseInteractionChromeMode? = nil
    private var hiddenPassiveTabGroupChromeIds: Set<ObjectIdentifier> = []

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

    private func orderOutPanels(id: ObjectIdentifier) {
        visualPanels[id]?.orderOut(nil)
        stripPanels[id]?.orderOut(nil)
    }

    private func refreshFrameOnlyChrome(strips: [WindowTabStripViewModel], activeIds: Set<ObjectIdentifier>) {
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

    private func refreshHiddenChrome(activeIds: Set<ObjectIdentifier>) {
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
private final class WindowTabGroupVisualPanel: NSPanelHud {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var currentContent: WindowTabGroupChromeContent? = nil
    private var currentPanelFrame: CGRect? = nil

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
        let panelFrame = strip.groupFrame.alignedToBackingPixels()
        let tabFrame = strip.frame.alignedToBackingPixels()
        let displayStrip = WindowTabStripViewModel(
            id: strip.id,
            workspaceName: strip.workspaceName,
            frame: tabFrame,
            groupFrame: panelFrame,
            activeWindowId: strip.activeWindowId,
            activeWindowCornerRadius: strip.activeWindowCornerRadius,
            tabs: strip.tabs,
            occludingFloatingWindowFrames: strip.occludingFloatingWindowFrames,
        )
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
private final class WindowTabStripPanel: NSPanelHud {
    private let hostingView = WindowTabStripHostingView(rootView: AnyView(EmptyView()))
    private var currentContent: WindowTabGroupChromeContent? = nil
    private var currentPanelFrame: CGRect? = nil
    private var externallyIgnoresMouseEvents = false
    private var tabStripIsOccludedByFloatingWindow = false

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
        let panelFrame = strip.groupFrame.alignedToBackingPixels()
        let tabFrame = strip.frame.alignedToBackingPixels()
        let displayStrip = WindowTabStripViewModel(
            id: strip.id,
            workspaceName: strip.workspaceName,
            frame: tabFrame,
            groupFrame: panelFrame,
            activeWindowId: strip.activeWindowId,
            activeWindowCornerRadius: strip.activeWindowCornerRadius,
            tabs: strip.tabs,
            occludingFloatingWindowFrames: strip.occludingFloatingWindowFrames,
        )
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

    private func updateMousePolicy() {
        let disabled = externallyIgnoresMouseEvents ||
            currentlyManipulatedWithMouseWindowId != nil ||
            tabStripIsOccludedByFloatingWindow
        ignoresMouseEvents = disabled
    }
}

private final class WindowTabStripHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
private func setWindowTabChromePanelFrame(_ frame: CGRect, on panel: NSPanelHud) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    panel.setFrame(frame, display: true, animate: false)
    panel.contentView?.layoutSubtreeIfNeeded()
    CATransaction.commit()
}

@MainActor
private func applyWindowTabVisualStackingPolicy(for strip: WindowTabStripViewModel, to panel: NSPanelHud) {
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
private func applyWindowTabStripStackingPolicy(for strip: WindowTabStripViewModel, to panel: NSPanelHud) {
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

private struct WindowTabGroupChromeContent: Equatable {
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

@MainActor
final class WindowTabDropPreviewPanel: NSPanelHud {
    static let shared = WindowTabDropPreviewPanel()

    private let compositorView = WindowIntentPreviewCompositorView()
    private var hasShownPreview = false
    private var currentPreviewKey: WindowIntentPreviewContentKey?

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowTabDropPreviewPanelId)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        backgroundColor = .clear
        // Keep window intent previews above app windows but below the sidebar,
        // because the hints target windows behind that sidebar.
        applyWinMuxLayer(.windowIntentPreview)
        contentView = compositorView
        compositorView.frame = contentView?.bounds ?? .zero
        compositorView.autoresizingMask = [.width, .height]
    }

    func show(_ preview: WindowTabDropPreviewViewModel) {
        let targetFrame = preview.containerFrame.alignedToBackingPixels()
        if frame.size == targetFrame.size {
            setFrameOrigin(targetFrame.origin)
        } else {
            setFrame(targetFrame, display: false, animate: false)
        }
        compositorView.frame = CGRect(origin: .zero, size: targetFrame.size)
        alphaValue = 1
        let previewKey = WindowIntentPreviewContentKey(model: preview)
        if currentPreviewKey != previewKey || !hasShownPreview {
            let animation: WindowIntentPreviewAnimation
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                animation = .none
            } else if hasShownPreview, currentPreviewKey?.canMorph(to: previewKey) == true {
                animation = .morph
            } else if !hasShownPreview {
                animation = .appear
            } else {
                animation = .none
            }
            compositorView.update(preview, animation: animation)
            currentPreviewKey = previewKey
        }
        if !isVisible || !hasShownPreview {
            orderFrontRegardless()
        }
        hasShownPreview = true
    }

    func hide() {
        compositorView.clear()
        hasShownPreview = false
        currentPreviewKey = nil
        alphaValue = 1
        orderOut(nil)
    }
}

// MARK: - Cursor Drag Proxy (follows cursor during sidebar-originated drags)

@MainActor
final class WindowDragCursorProxyPanel: NSPanelHud {
    static let shared = WindowDragCursorProxyPanel()

    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var currentContent: WindowDragCursorProxyContent? = nil
    private var proxySize: CGSize = .zero

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowDragCursorProxyPanelId)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        backgroundColor = .clear
        applyWinMuxLayer(.dragCursorProxy)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func show(label: String, isGroup: Bool, mouseScreenPoint: CGPoint) {
        let nextContent = WindowDragCursorProxyContent(label: label, isGroup: isGroup)
        if currentContent != nextContent {
            hostingView.rootView = AnyView(WindowDragCursorProxyView(label: label, isGroup: isGroup))
            currentContent = nextContent
        }
        proxySize = CGSize(
            width: min(max(CGFloat(label.count) * 7 + 36, 80), 200),
            height: 28,
        )
        updateFrame(mouseScreenPoint: mouseScreenPoint)
        startFollowingMouseIfNeeded()
        orderFrontRegardless()
    }

    func hide() {
        stopFollowingMouse()
        currentContent = nil
        orderOut(nil)
    }

    private func startFollowingMouseIfNeeded() {
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in
            self?.updateFrame(mouseScreenPoint: NSEvent.mouseLocation)
        }
    }

    private func stopFollowingMouse() {
        DisplayRefreshDriver.shared.remove(owner: self)
    }

    private func updateFrame(mouseScreenPoint: CGPoint) {
        guard proxySize.width > 0, proxySize.height > 0 else { return }
        let targetFrame = windowDragCursorProxyFrame(
            mouseScreenPoint: mouseScreenPoint,
            proxySize: proxySize,
        )
        if frame.size == targetFrame.size {
            setFrameOrigin(targetFrame.origin)
        } else {
            setFrame(targetFrame, display: false, animate: false)
        }
    }
}

private struct WindowDragCursorProxyContent: Equatable {
    let label: String
    let isGroup: Bool
}

private func windowDragCursorProxyFrame(mouseScreenPoint: CGPoint, proxySize: CGSize) -> CGRect {
    let screenFrame = NSScreen.screens
        .first(where: { $0.frame.contains(mouseScreenPoint) })?
        .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

    var x = mouseScreenPoint.x + 14
    var y = mouseScreenPoint.y - proxySize.height - 6

    if x + proxySize.width > screenFrame.maxX {
        x = mouseScreenPoint.x - proxySize.width - 14
    }
    if y < screenFrame.minY {
        y = mouseScreenPoint.y + 6
    }

    return CGRect(
        x: x,
        y: y,
        width: proxySize.width,
        height: proxySize.height,
    )
}

private struct WindowDragCursorProxyView: View {
    let label: String
    let isGroup: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isGroup ? "square.stack" : "macwindow")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(mattePanelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(mattePanelSeparator, lineWidth: 0.7)
                }
                .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2),
        )
    }
}

struct WindowTabDropPreviewViewModel: Equatable {
    let containerFrame: CGRect
    let frame: CGRect
    let title: String
    let subtitle: String
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let isGroup: Bool
    let referenceWindowId: UInt32?
    let isPointerSettled: Bool
    let zones: [WindowTabDropPreviewZoneViewModel]
}

struct WindowTabDropPreviewZoneViewModel: Equatable {
    let frame: CGRect
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let isActive: Bool
}

enum WindowTabDropPreviewStyle: Equatable {
    case tabInsert
    case detach
    case stackSplit
    case swap
    case workspaceMove
    case sidebarWorkspaceMove
}

enum WindowTabDropPreviewGeometry: Equatable {
    case rounded
    case tabStrip
    case splitLeft
    case splitRight
    case splitAbove
    case splitBelow

    fileprivate func cornerRadii(radius: CGFloat) -> PreviewCornerRadii {
        switch self {
            case .rounded:
                PreviewCornerRadii.uniform(radius)
            case .tabStrip:
                PreviewCornerRadii(topLeft: radius, topRight: radius, bottomRight: 0, bottomLeft: 0)
            case .splitLeft:
                PreviewCornerRadii(topLeft: radius, topRight: 0, bottomRight: 0, bottomLeft: radius)
            case .splitRight:
                PreviewCornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: 0)
            case .splitAbove:
                PreviewCornerRadii(topLeft: radius, topRight: radius, bottomRight: 0, bottomLeft: 0)
            case .splitBelow:
                PreviewCornerRadii(topLeft: 0, topRight: 0, bottomRight: radius, bottomLeft: radius)
        }
    }
}

struct WindowIntentPreviewGuideLine: Equatable {
    let start: CGPoint
    let end: CGPoint
}

func windowIntentPreviewGuideLine(
    for geometry: WindowTabDropPreviewGeometry,
    in size: CGSize,
) -> WindowIntentPreviewGuideLine? {
    switch geometry {
        case .splitLeft:
            WindowIntentPreviewGuideLine(
                start: CGPoint(x: max(size.width - 1, 0), y: 8),
                end: CGPoint(x: max(size.width - 1, 0), y: max(size.height - 8, 8)),
            )
        case .splitRight:
            WindowIntentPreviewGuideLine(
                start: CGPoint(x: 1, y: 8),
                end: CGPoint(x: 1, y: max(size.height - 8, 8)),
            )
        case .splitAbove:
            WindowIntentPreviewGuideLine(
                start: CGPoint(x: 8, y: max(size.height - 1, 0)),
                end: CGPoint(x: max(size.width - 8, 8), y: max(size.height - 1, 0)),
            )
        case .splitBelow:
            WindowIntentPreviewGuideLine(
                start: CGPoint(x: 8, y: 1),
                end: CGPoint(x: max(size.width - 8, 8), y: 1),
            )
        case .tabStrip:
            WindowIntentPreviewGuideLine(
                start: CGPoint(x: 10, y: max(size.height - 1, 1)),
                end: CGPoint(x: max(size.width - 10, 10), y: max(size.height - 1, 1)),
            )
        case .rounded:
            nil
    }
}

func windowIntentPreviewSymbolName(for style: WindowTabDropPreviewStyle, isGroup: Bool) -> String {
    switch style {
        case .tabInsert:
            "square.stack.3d.up"
        case .detach:
            "arrow.up.left.and.arrow.down.right"
        case .stackSplit:
            "rectangle.split.2x1"
        case .swap:
            "arrow.left.arrow.right"
        case .workspaceMove, .sidebarWorkspaceMove:
            isGroup ? "rectangle.stack.badge.plus" : "macwindow.badge.plus"
    }
}

@MainActor
private final class WindowIntentPreviewCompositorView: NSView {
    private let surfaceLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private let innerStrokeLayer = CAShapeLayer()
    private let accentStrokeLayer = CAShapeLayer()
    private let activeStrokeLayer = CAShapeLayer()
    private let guideLayer = CAShapeLayer()
    private let activeGuideLayer = CAShapeLayer()
    private var currentModel: WindowTabDropPreviewViewModel?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let backingLayer = CALayer()
        backingLayer.masksToBounds = false
        backingLayer.isGeometryFlipped = true
        layer = backingLayer
        configureLayers(backingLayer)

        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ model: WindowTabDropPreviewViewModel, animation: WindowIntentPreviewAnimation) {
        currentModel = model
        isHidden = false
        render(model, animation: animation)
    }

    func clear() {
        currentModel = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in previewLayers {
            layer.path = nil
            layer.isHidden = true
        }
        self.layer?.removeAnimation(forKey: "intentPreviewAppear")
        self.layer?.opacity = 1
        isHidden = true
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        if let currentModel {
            render(currentModel, animation: .none)
        }
    }

    private var previewLayers: [CAShapeLayer] {
        [
            surfaceLayer,
            highlightLayer,
            innerStrokeLayer,
            accentStrokeLayer,
            activeStrokeLayer,
            guideLayer,
            activeGuideLayer,
        ]
    }

    private func configureLayers(_ backingLayer: CALayer) {
        disableWindowIntentPreviewLayerActions(backingLayer)
        surfaceLayer.fillColor = WindowIntentPreviewPalette.fill
        highlightLayer.fillColor = NSColor.clear.cgColor
        innerStrokeLayer.fillColor = NSColor.clear.cgColor
        innerStrokeLayer.strokeColor = WindowIntentPreviewPalette.innerStroke
        innerStrokeLayer.lineWidth = 0.55
        accentStrokeLayer.fillColor = NSColor.clear.cgColor
        accentStrokeLayer.lineWidth = 0.85
        activeStrokeLayer.fillColor = NSColor.clear.cgColor
        activeStrokeLayer.lineWidth = 1.45
        guideLayer.fillColor = NSColor.clear.cgColor
        guideLayer.lineWidth = 1.5
        guideLayer.lineCap = .round
        activeGuideLayer.fillColor = NSColor.clear.cgColor
        activeGuideLayer.lineWidth = 1.65
        activeGuideLayer.lineCap = .round
        for layer in previewLayers {
            layer.isHidden = true
            disableWindowIntentPreviewLayerActions(layer)
            backingLayer.addSublayer(layer)
        }
    }

    private func render(_ model: WindowTabDropPreviewViewModel, animation: WindowIntentPreviewAnimation) {
        let scale = updateContentsScale()
        let zones = localZones(for: model, scale: scale)
        let activeZones = zones.filter(\.isActive)
        let surfacePath = combinedSurfacePath(for: zones, inset: 0)
        let activeSurfacePath = combinedSurfacePath(for: activeZones, inset: 0)
        let insetPath = combinedSurfacePath(for: zones, inset: 1)
        let guidePath = combinedGuidePath(for: zones)
        let activeGuidePath = combinedGuidePath(for: activeZones)
        let appearingStartZones: [WindowIntentPreviewLocalZone]
        let appearingActiveZones: [WindowIntentPreviewLocalZone]
        if animation == .appear {
            appearingStartZones = appearanceStartZones(for: zones)
            appearingActiveZones = appearingStartZones.filter(\.isActive)
        } else {
            appearingStartZones = []
            appearingActiveZones = []
        }
        let appearingSurfacePath = combinedSurfacePath(for: appearingStartZones, inset: 0)
        let appearingActiveSurfacePath = combinedSurfacePath(for: appearingActiveZones, inset: 0)
        let appearingInsetPath = combinedSurfacePath(for: appearingStartZones, inset: 1)
        let appearingGuidePath = combinedGuidePath(for: appearingStartZones)
        let appearingActiveGuidePath = combinedGuidePath(for: appearingActiveZones)
        let style = WindowIntentPreviewLayerStyle(style: model.style, isPointerSettled: model.isPointerSettled)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in previewLayers {
            layer.frame = bounds
            layer.contentsScale = scale
            layer.isHidden = false
        }
        setPath(surfacePath, on: surfaceLayer, animation: animation, key: "surfacePath", appearingStartPath: appearingSurfacePath)
        surfaceLayer.fillColor = WindowIntentPreviewPalette.fill
        setPath(surfacePath, on: highlightLayer, animation: animation, key: "highlightPath", appearingStartPath: appearingSurfacePath)
        highlightLayer.fillColor = WindowIntentPreviewPalette.highlight(alpha: style.highlightAlpha)
        setPath(insetPath, on: innerStrokeLayer, animation: animation, key: "innerStrokePath", appearingStartPath: appearingInsetPath)
        setPath(surfacePath, on: accentStrokeLayer, animation: animation, key: "accentPath", appearingStartPath: appearingSurfacePath)
        accentStrokeLayer.strokeColor = WindowIntentPreviewPalette.accent(alpha: style.inactiveStrokeAlpha)
        setPath(activeSurfacePath, on: activeStrokeLayer, animation: animation, key: "activeStrokePath", appearingStartPath: appearingActiveSurfacePath)
        activeStrokeLayer.strokeColor = WindowIntentPreviewPalette.accent(alpha: style.strokeAlpha)
        setPath(guidePath, on: guideLayer, animation: animation, key: "guidePath", appearingStartPath: appearingGuidePath)
        guideLayer.strokeColor = WindowIntentPreviewPalette.accent(alpha: style.inactiveGuideAlpha)
        setPath(activeGuidePath, on: activeGuideLayer, animation: animation, key: "activeGuidePath", appearingStartPath: appearingActiveGuidePath)
        activeGuideLayer.strokeColor = WindowIntentPreviewPalette.accent(alpha: style.guideAlpha)
        CATransaction.commit()
        if animation == .appear {
            animateInitialOpacity()
        }
    }

    private func setPath(
        _ path: CGPath?,
        on layer: CAShapeLayer,
        animation: WindowIntentPreviewAnimation,
        key: String,
        appearingStartPath: CGPath?
    ) {
        let currentPresentationPath = layer.presentation()?.path
        let currentModelPath = layer.path
        layer.removeAnimation(forKey: key)
        layer.path = path
        let fromPath: CGPath?
        let duration: CFTimeInterval
        switch animation {
            case .none:
                return
            case .morph:
                fromPath = currentPresentationPath ?? currentModelPath
                duration = 0.145
            case .appear:
                fromPath = appearingStartPath
                duration = 0.16
        }
        guard let fromPath, let path else { return }

        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = fromPath
        pathAnimation.toValue = path
        pathAnimation.duration = duration
        pathAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        layer.add(pathAnimation, forKey: key)
    }

    private func animateInitialOpacity() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "intentPreviewAppear")
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.72
        opacity.toValue = 1
        opacity.duration = 0.13
        opacity.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        layer.opacity = 1
        layer.add(opacity, forKey: "intentPreviewAppear")
    }

    private func updateContentsScale() -> CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func localZones(for model: WindowTabDropPreviewViewModel, scale: CGFloat) -> [WindowIntentPreviewLocalZone] {
        let zones = model.zones.isEmpty
            ? [WindowTabDropPreviewZoneViewModel(frame: model.frame, style: model.style, geometry: model.geometry, isActive: true)]
            : model.zones
        return zones.map { zone in
            WindowIntentPreviewLocalZone(
                frame: alignToBackingPixels(localFrame(for: zone.frame, containerFrame: model.containerFrame), scale: scale),
                style: zone.style,
                geometry: zone.geometry,
                isActive: zone.isActive,
            )
        }
    }

    private func localFrame(for screenFrame: CGRect, containerFrame: CGRect) -> CGRect {
        let localMinX = screenFrame.minX - containerFrame.minX
        let localMinY = containerFrame.height - (screenFrame.maxY - containerFrame.minY)
        return CGRect(
            x: localMinX,
            y: localMinY,
            width: screenFrame.width,
            height: screenFrame.height,
        )
    }

    private func appearanceStartZones(for zones: [WindowIntentPreviewLocalZone]) -> [WindowIntentPreviewLocalZone] {
        zones.map { zone in
            let startWidth = max(zone.frame.width * 0.88, min(zone.frame.width, 2))
            let startHeight = max(zone.frame.height * 0.88, min(zone.frame.height, 2))
            let startFrame = CGRect(
                x: zone.frame.midX - startWidth / 2,
                y: zone.frame.midY - startHeight / 2,
                width: startWidth,
                height: startHeight,
            )
            return WindowIntentPreviewLocalZone(
                frame: startFrame,
                style: zone.style,
                geometry: zone.geometry,
                isActive: zone.isActive,
            )
        }
    }

    private func combinedSurfacePath(for zones: [WindowIntentPreviewLocalZone], inset: CGFloat) -> CGPath? {
        guard !zones.isEmpty else { return nil }
        let path = CGMutablePath()
        for zone in zones {
            let zoneFrame = zone.frame.insetBy(dx: inset, dy: inset)
            guard zoneFrame.width > 0, zoneFrame.height > 0 else { continue }
            let clampedRadius = min(windowTabPreviewCornerRadius, max(0, min(zoneFrame.width, zoneFrame.height) / 2))
            path.addPath(CGPath(
                roundedRect: zoneFrame,
                cornerWidth: max(clampedRadius - inset, 0),
                cornerHeight: max(clampedRadius - inset, 0),
                transform: nil,
            ))
        }
        return path
    }

    private func combinedGuidePath(for zones: [WindowIntentPreviewLocalZone]) -> CGPath? {
        let path = CGMutablePath()
        var hasPath = false
        for zone in zones {
            guard let line = windowIntentPreviewGuideLine(for: zone.geometry, in: zone.frame.size) else {
                continue
            }
            path.move(to: CGPoint(x: zone.frame.minX + line.start.x, y: zone.frame.minY + line.start.y))
            path.addLine(to: CGPoint(x: zone.frame.minX + line.end.x, y: zone.frame.minY + line.end.y))
            hasPath = true
        }
        guard hasPath else { return nil }
        return path
    }

    private func alignToBackingPixels(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let alignedMinX = (rect.minX * scale).rounded() / scale
        let alignedMinY = (rect.minY * scale).rounded() / scale
        let alignedMaxX = (rect.maxX * scale).rounded() / scale
        let alignedMaxY = (rect.maxY * scale).rounded() / scale
        return CGRect(
            x: alignedMinX,
            y: alignedMinY,
            width: max(alignedMaxX - alignedMinX, 0),
            height: max(alignedMaxY - alignedMinY, 0),
        )
    }
}

private struct WindowIntentPreviewLocalZone {
    let frame: CGRect
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let isActive: Bool
}

private enum WindowIntentPreviewAnimation {
    case none
    case appear
    case morph
}

private struct WindowIntentPreviewContentKey: Equatable {
    let containerSize: CGSize
    let referenceWindowId: UInt32?
    let frame: CGRect
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let zones: [WindowTabDropPreviewZoneViewModel]

    init(model: WindowTabDropPreviewViewModel) {
        containerSize = model.containerFrame.size
        referenceWindowId = model.referenceWindowId
        frame = model.frame
        style = model.style
        geometry = model.geometry
        zones = model.zones
    }

    func canMorph(to next: WindowIntentPreviewContentKey) -> Bool {
        referenceWindowId == next.referenceWindowId
            && containerSize.isNearlyEqual(to: next.containerSize, tolerance: 1)
    }
}

private extension CGSize {
    func isNearlyEqual(to other: CGSize, tolerance: CGFloat) -> Bool {
        abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

private struct WindowIntentPreviewLayerStyle {
    let highlightAlpha: CGFloat
    let inactiveStrokeAlpha: CGFloat
    let strokeAlpha: CGFloat
    let inactiveGuideAlpha: CGFloat
    let guideAlpha: CGFloat

    init(style: WindowTabDropPreviewStyle, isPointerSettled _: Bool) {
        let boost: CGFloat = 1
        switch style {
            case .tabInsert:
                highlightAlpha = 0.07 * boost
                inactiveStrokeAlpha = 0.16
                strokeAlpha = 0.36 * boost
                inactiveGuideAlpha = 0.12
                guideAlpha = 0.34 * boost
            case .detach:
                highlightAlpha = 0.06 * boost
                inactiveStrokeAlpha = 0.14
                strokeAlpha = 0.32 * boost
                inactiveGuideAlpha = 0.10
                guideAlpha = 0.28 * boost
            case .stackSplit:
                highlightAlpha = 0.065 * boost
                inactiveStrokeAlpha = 0.17
                strokeAlpha = 0.38 * boost
                inactiveGuideAlpha = 0.12
                guideAlpha = 0.36 * boost
            case .swap:
                highlightAlpha = 0.05 * boost
                inactiveStrokeAlpha = 0.15
                strokeAlpha = 0.34 * boost
                inactiveGuideAlpha = 0
                guideAlpha = 0
            case .workspaceMove, .sidebarWorkspaceMove:
                highlightAlpha = 0.06 * boost
                inactiveStrokeAlpha = 0.14
                strokeAlpha = 0.32 * boost
                inactiveGuideAlpha = 0.10
                guideAlpha = 0.28 * boost
        }
    }
}

enum WindowIntentPreviewPalette {
    static let fillColor = mattePanelNSColor
    static let fill = fillColor.cgColor
    static let innerStroke = NSColor.white.withAlphaComponent(0.025).cgColor
    static let accentColor = fillColor

    static func highlight(alpha: CGFloat) -> CGColor {
        NSColor.white.withAlphaComponent(min(max(alpha * 0.24, 0), 0.035)).cgColor
    }

    static func accent(alpha: CGFloat) -> CGColor {
        accentColor.cgColor
    }
}

private final class WindowIntentPreviewDisabledLayerAction: NSObject, CAAction {
    func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {}
}

private func disableWindowIntentPreviewLayerActions(_ layer: CALayer) {
    let action = WindowIntentPreviewDisabledLayerAction()
    layer.actions = [
        "backgroundColor": action,
        "bounds": action,
        "contents": action,
        "frame": action,
        "hidden": action,
        "opacity": action,
        "path": action,
        "position": action,
        "strokeColor": action,
        "fillColor": action,
        "sublayers": action,
    ]
}

@MainActor
private func focusWindowFromTabStrip(_ windowId: UInt32, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId),
                  let liveFocus = window.toLiveFocusOrNil()
            else {
                _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
                return
            }
            window.markAsMostRecentChild()
            _ = setFocus(to: liveFocus)
            window.nativeFocus()
        }
    }
}

@MainActor
private func focusWindowFromTabStripClick(_ windowId: UInt32, fallbackWorkspace: String) {
    if isWindowTabStripDragInProgress(), !isLeftMouseButtonDown {
        cancelManipulatedWithMouseState()
    }
    focusWindowFromTabStrip(windowId, fallbackWorkspace: fallbackWorkspace)
}

@MainActor
private func removeWindowFromTabStrip(_ windowId: UInt32, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId) else {
                _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
                return
            }
            _ = removeWindowFromTabStack(window)
            window.nativeFocus()
        }
    }
}

@MainActor
private func reorderTabInStrip(_ windowId: UInt32, toIndex targetIndex: Int) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId),
                  let parent = window.parent as? TilingContainer,
                  parent.layout == .tabGroup,
                  let currentIndex = window.ownIndex
            else { return }
            let clampedTarget = max(0, min(targetIndex, parent.children.count - 1))
            guard clampedTarget != currentIndex else { return }
            let binding = window.unbindFromParent()
            window.bind(to: parent, adaptiveWeight: binding.adaptiveWeight, index: clampedTarget)
            window.markAsMostRecentChild()
            _ = window.focusWindow()
        }
    }
}

@MainActor
private func updateDetachedTabFromTabStrip(_ windowId: UInt32) {
    guard let window = Window.get(byId: windowId) else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    beginWindowMoveWithMouseSessionIfNeeded(
        windowId: window.windowId,
        subject: .window,
        detachOrigin: .tabStrip,
        startedInSidebar: false,
        anchorRect: resolvedDraggedWindowAnchorRect(for: window, subject: .window),
        refreshActualRects: false,
    )
    WindowMouseInteractionDriver.shared.startMove(
        windowId: window.windowId,
        subject: .window,
        detachOrigin: .tabStrip,
        startedInSidebar: false,
    )
}

@MainActor
func shouldDeferWindowTabStripGroupDragToDetachedTabDrag() -> Bool {
    getCurrentMouseManipulationKind() == .move &&
        getCurrentMouseDragSubject() == .window &&
        getCurrentMouseTabDetachOrigin() == .tabStrip
}

func isWindowTabStripDragInProgress(
    kind: MouseManipulationKind,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    startedInSidebar: Bool,
) -> Bool {
    guard kind == .move, !startedInSidebar else { return false }
    return detachOrigin == .tabStrip || subject == .group
}

@MainActor
func isWindowTabStripDragInProgress() -> Bool {
    isWindowTabStripDragInProgress(
        kind: getCurrentMouseManipulationKind(),
        subject: getCurrentMouseDragSubject(),
        detachOrigin: getCurrentMouseTabDetachOrigin(),
        startedInSidebar: getCurrentMouseDragStartedInSidebar(),
    )
}

@MainActor
func shouldHandleWindowTabStripGroupDragEnd() -> Bool {
    !shouldDeferWindowTabStripGroupDragToDetachedTabDrag()
}

@MainActor
private func updateMoveFromTabStrip(_ windowId: UInt32) {
    guard let window = Window.get(byId: windowId) else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    if shouldDeferWindowTabStripGroupDragToDetachedTabDrag() {
        return
    }
    beginWindowMoveWithMouseSessionIfNeeded(
        windowId: window.windowId,
        subject: .group,
        detachOrigin: .window,
        startedInSidebar: false,
        anchorRect: resolvedDraggedWindowAnchorRect(for: window, subject: .group),
        refreshActualRects: false,
    )
    WindowMouseInteractionDriver.shared.startMove(
        windowId: window.windowId,
        subject: .group,
        detachOrigin: .window,
        startedInSidebar: false,
    )
}

@MainActor
private func finishMoveFromTabStrip() {
    guard shouldHandleWindowTabStripGroupDragEnd() else { return }
    Task { @MainActor in
        try? await resetManipulatedWithMouseIfPossible()
    }
}

@MainActor
private func shouldPromoteTabStripDragToGroup(windowId: UInt32) -> Bool {
    if shouldContinueCurrentGroupDrag(windowId: windowId) {
        return true
    }
    guard let window = Window.get(byId: windowId) else { return false }
    let isOptionPressed = currentSessionModifierFlags().contains(.maskAlternate)
    return shouldPromoteWindowDragToTabGroupDrag(
        isOptionPressed: isOptionPressed,
        isTabbedWindow: isWindowInDraggableTabGroup(window),
    )
}

@MainActor
private func shouldAllowTabStripChromeGroupDrag(windowId: UInt32) -> Bool {
    if shouldContinueCurrentGroupDrag(windowId: windowId) {
        return true
    }
    guard let window = Window.get(byId: windowId) else { return false }
    return isWindowInDraggableTabGroup(window)
}

// MARK: - Constants

private let windowTabPreviewCornerRadius: CGFloat = 12
private let windowTabStripContentHorizontalPadding: CGFloat = 2
private let windowTabStripGroupHandleWidth: CGFloat = 2
private let windowTabStripCornerRadius: CGFloat = 12
private let windowTabStripInnerCornerRadius: CGFloat = 12
private let windowTabStripTabSpacing: CGFloat = 8
private let windowTabStripPreferredTabWidth: CGFloat = 240
private let windowTabStripMinimumTabWidth: CGFloat = 132
private let windowTabStripScrollFadeWidth: CGFloat = 22
private let windowTabStripScrollOriginTolerance: CGFloat = 1
private let windowTabGroupFrameStrokeWidth: CGFloat = 0.5
private let windowTabGroupFrameInnerStrokeWidth: CGFloat = 0.5
private let windowTabGroupFrameMaxInnerCornerRadius: CGFloat = 22
private let windowTabGroupFrameMaxTopInnerCornerRadius: CGFloat = 40
private let windowTabGroupCornerShieldOverreach: CGFloat = 7
private let windowTabPillAnimation: Animation = .spring(response: 0.28, dampingFraction: 0.72, blendDuration: 0.08)
private let windowTabReducedMotionAnimation: Animation = .easeOut(duration: 0.12)

func windowTabStripContentPadding() -> CGFloat {
    windowTabStripContentHorizontalPadding
}

func windowTabStripReservedGroupHandleWidth() -> CGFloat {
    windowTabStripGroupHandleWidth
}

func windowTabStripAvailableTabsWidth(stripWidth: CGFloat) -> CGFloat {
    max(
        0,
        stripWidth
            - (windowTabStripReservedGroupHandleWidth() * 2)
            - (windowTabStripContentHorizontalPadding * 2),
    )
}

func windowTabStripTabWidth(stripWidth: CGFloat, count: Int) -> CGFloat {
    let availableWidth = windowTabStripAvailableTabsWidth(stripWidth: stripWidth)
    guard availableWidth > 0 else { return windowTabStripPreferredTabWidth }
    return max(windowTabStripMinimumTabWidth, min(windowTabStripPreferredTabWidth, availableWidth))
}

func windowTabResolvedScrollFadeWidth(stripWidth: CGFloat) -> CGFloat {
    min(windowTabStripScrollFadeWidth, max(stripWidth / 5, 0))
}

func windowTabLeadingScrollFadeWidth(isScrollable: Bool, contentMinX: CGFloat, stripWidth: CGFloat) -> CGFloat {
    guard isScrollable, contentMinX < -windowTabStripScrollOriginTolerance else { return 0 }
    return windowTabResolvedScrollFadeWidth(stripWidth: stripWidth)
}

func windowTabTrailingScrollFadeWidth(isScrollable: Bool, stripWidth: CGFloat) -> CGFloat {
    isScrollable ? windowTabResolvedScrollFadeWidth(stripWidth: stripWidth) : 0
}

// MARK: - Tab Strip View (manages reorder drag state for all tabs)

private let tabReorderVerticalEscapeThreshold: CGFloat = 18

private struct WindowTabGroupVisualView: View {
    let strip: WindowTabStripViewModel
    let drawsMockTabs: Bool

    var body: some View {
        GeometryReader { proxy in
            WindowTabGroupFrameView(
                strip: strip,
                groupSize: proxy.size,
                drawsMockTabs: drawsMockTabs,
            )
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .windowTabOcclusionMasked(
            panelFrame: strip.groupFrame,
            occludingScreenFrames: strip.occludingFloatingWindowFrames,
        )
    }
}

private struct WindowTabGroupFrameView: View {
    let strip: WindowTabStripViewModel
    let groupSize: CGSize
    let drawsMockTabs: Bool

    var body: some View {
        let tabHeight = min(strip.frame.height, groupSize.height)
        let innerFrame = windowTabGroupInnerAppFrame(groupSize: groupSize, tabHeight: tabHeight)
        let appCornerRadius = strip.activeWindowCornerRadius
        let topInnerCornerRadius = windowTabGroupTopInnerCornerRadius(appCornerRadius)
        let outerTopRadius = windowTabGroupOuterCornerRadius(innerCornerRadius: topInnerCornerRadius)

        let bottomOuterRadius = appCornerRadius + windowTabGroupShellHorizontalInset()
        let outerRadii = PreviewCornerRadii(
            topLeft: outerTopRadius,
            topRight: outerTopRadius,
            bottomRight: bottomOuterRadius,
            bottomLeft: bottomOuterRadius
        )

        let innerRadii = PreviewCornerRadii(
            topLeft: topInnerCornerRadius,
            topRight: topInnerCornerRadius,
            bottomRight: appCornerRadius,
            bottomLeft: appCornerRadius
        )

        let shellShape = WindowTabGroupShellShape(
            outerRadii: outerRadii,
            innerRect: innerFrame,
            innerRadii: innerRadii
        )
        let outerShape = WindowTabDropOutlineShape(cornerRadii: outerRadii)

        ZStack(alignment: .topLeading) {
            shellShape
                .fill(mattePanelFill, style: FillStyle(eoFill: true))

            WindowTabGroupCornerShieldShape(
                innerRect: innerFrame,
                topRadius: windowTabGroupTopCornerShieldRadius(topInnerCornerRadius),
                bottomRadius: windowTabGroupBottomCornerShieldRadius(appCornerRadius)
            )
            .fill(mattePanelFill, style: FillStyle(eoFill: true))

            if drawsMockTabs {
                WindowTabGroupMockTabsView(
                    strip: strip,
                    stripWidth: groupSize.width,
                    stripHeight: tabHeight,
                )
                .frame(width: groupSize.width, height: tabHeight, alignment: .topLeading)
            }

            // Outer edge
            outerShape
                .strokeBorder(mattePanelBorder, lineWidth: windowTabGroupFrameStrokeWidth)

            // Inner window boundary
            WindowTabDropOutlineShape(cornerRadii: innerRadii)
                .strokeBorder(mattePanelInsetShadow, lineWidth: windowTabGroupFrameInnerStrokeWidth)
                .frame(width: innerFrame.width, height: innerFrame.height)
                .offset(x: innerFrame.minX, y: innerFrame.minY)
        }
        .frame(width: groupSize.width, height: groupSize.height)
        .shadow(color: Color.black.opacity(0.10), radius: 6, y: 2)
        .allowsHitTesting(false)
    }
}

private struct WindowTabGroupMockTabsView: View {
    let strip: WindowTabStripViewModel
    let stripWidth: CGFloat
    let stripHeight: CGFloat

    var body: some View {
        let tabCount = max(strip.tabs.count, 1)
        let tabWidth = windowTabStripTabWidth(stripWidth: stripWidth, count: tabCount)
        let itemHeight = max(stripHeight - 4, 18)
        let visibleCount = windowTabGroupMockVisibleTabCount(
            stripWidth: stripWidth,
            tabWidth: tabWidth,
            tabCount: tabCount,
        )
        let visibleTabs = Array(strip.tabs.prefix(visibleCount))

        HStack(spacing: 0) {
            Color.clear
                .frame(width: windowTabStripReservedGroupHandleWidth())

            HStack(spacing: windowTabStripTabSpacing) {
                if visibleTabs.isEmpty {
                    WindowTabMockPillView(isActive: true)
                        .frame(width: tabWidth, height: itemHeight)
                } else {
                    ForEach(Array(visibleTabs.enumerated()), id: \.element.windowId) { index, tab in
                        WindowTabMockPillView(isActive: tab.isActive || (strip.activeWindowId == nil && index == 0))
                            .frame(width: tabWidth, height: itemHeight)
                    }
                }
            }
            .padding(.horizontal, windowTabStripContentHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            Color.clear
                .frame(width: windowTabStripReservedGroupHandleWidth())
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(width: stripWidth, height: stripHeight, alignment: .topLeading)
        .allowsHitTesting(false)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct WindowTabMockPillView: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.14 : 0.07))
                .padding(.vertical, 2)

            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(isActive ? 0.12 : 0.07), lineWidth: 0.5)
                .padding(.vertical, 2)
        }
    }
}

private func windowTabGroupMockVisibleTabCount(stripWidth: CGFloat, tabWidth: CGFloat, tabCount: Int) -> Int {
    let requestedCount = max(tabCount, 1)
    let availableWidth = windowTabStripAvailableTabsWidth(stripWidth: stripWidth)
    guard availableWidth > 0 else { return 1 }
    let effectiveTabWidth = max(tabWidth + windowTabStripTabSpacing, 1)
    let fittingCount = Int(ceil((availableWidth + windowTabStripTabSpacing) / effectiveTabWidth))
    return max(1, min(requestedCount, fittingCount))
}

@MainActor
func windowTabGroupAppCornerRadius(activeWindowId: UInt32?) -> CGFloat {
    let radius = activeWindowId.map(estimatedWindowPreviewCornerRadius) ?? windowTabPreviewCornerRadius
    return min(max(radius, 6), windowTabGroupFrameMaxInnerCornerRadius)
}

func windowTabGroupOuterCornerRadius(innerCornerRadius _: CGFloat) -> CGFloat {
    windowTabStripCornerRadius
}

func windowTabGroupTopInnerCornerRadius(_ appCornerRadius: CGFloat) -> CGFloat {
    min(
        max(appCornerRadius + windowTabGroupShellHorizontalInset() + 14, windowTabStripCornerRadius + 18),
        windowTabGroupFrameMaxTopInnerCornerRadius
    )
}

private func windowTabGroupTopCornerShieldRadius(_ topInnerCornerRadius: CGFloat) -> CGFloat {
    min(topInnerCornerRadius + windowTabGroupCornerShieldOverreach, windowTabGroupFrameMaxTopInnerCornerRadius)
}

private func windowTabGroupBottomCornerShieldRadius(_ appCornerRadius: CGFloat) -> CGFloat {
    min(
        appCornerRadius + windowTabGroupCornerShieldOverreach,
        windowTabGroupFrameMaxInnerCornerRadius + windowTabGroupCornerShieldOverreach
    )
}

private func windowTabGroupInnerAppFrame(groupSize: CGSize, tabHeight: CGFloat) -> CGRect {
    let horizontalInset = min(windowTabGroupShellHorizontalInset(), groupSize.width / 2)
    let contentTop = min(tabHeight + windowTabGroupShellTopInset(), groupSize.height)
    let availableHeight = max(groupSize.height - contentTop, 0)
    let bottomInset = min(windowTabGroupShellBottomInset(), availableHeight)

    return CGRect(
        x: horizontalInset,
        y: contentTop,
        width: max(groupSize.width - horizontalInset * 2, 0),
        height: max(availableHeight - bottomInset, 0)
    )
}

private struct WindowTabGroupShellShape: Shape {
    let outerRadii: PreviewCornerRadii
    let innerRect: CGRect
    let innerRadii: PreviewCornerRadii

    func path(in rect: CGRect) -> Path {
        var path = WindowTabDropOutlineShape(cornerRadii: outerRadii).path(in: rect)
        if innerRect.width > 0, innerRect.height > 0 {
            path.addPath(WindowTabDropOutlineShape(cornerRadii: innerRadii).path(in: innerRect))
        }
        return path
    }
}

private struct WindowTabGroupCornerShieldShape: Shape {
    let innerRect: CGRect
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    func path(in _: CGRect) -> Path {
        var path = Path()
        guard innerRect.width > 0, innerRect.height > 0 else { return path }
        let maxRadius = min(innerRect.width / 2, innerRect.height / 2)
        let resolvedTopRadius = min(topRadius, maxRadius)
        let resolvedBottomRadius = min(bottomRadius, maxRadius)

        if resolvedTopRadius > 0 {
            addTopLeftShield(to: &path, radius: resolvedTopRadius)
            addTopRightShield(to: &path, radius: resolvedTopRadius)
        }
        if resolvedBottomRadius > 0 {
            addBottomLeftShield(to: &path, radius: resolvedBottomRadius)
            addBottomRightShield(to: &path, radius: resolvedBottomRadius)
        }
        return path
    }

    private func addTopLeftShield(to path: inout Path, radius: CGFloat) {
        let rect = CGRect(x: innerRect.minX, y: innerRect.minY, width: radius, height: radius)
        let center = CGPoint(x: innerRect.minX + radius, y: innerRect.minY + radius)
        path.addRect(rect)
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: innerRect.minY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(180),
            clockwise: true,
        )
        path.closeSubpath()
    }

    private func addTopRightShield(to path: inout Path, radius: CGFloat) {
        let rect = CGRect(x: innerRect.maxX - radius, y: innerRect.minY, width: radius, height: radius)
        let center = CGPoint(x: innerRect.maxX - radius, y: innerRect.minY + radius)
        path.addRect(rect)
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: innerRect.minY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false,
        )
        path.closeSubpath()
    }

    private func addBottomLeftShield(to path: inout Path, radius: CGFloat) {
        let rect = CGRect(x: innerRect.minX, y: innerRect.maxY - radius, width: radius, height: radius)
        let center = CGPoint(x: innerRect.minX + radius, y: innerRect.maxY - radius)
        path.addRect(rect)
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: innerRect.maxY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false,
        )
        path.closeSubpath()
    }

    private func addBottomRightShield(to path: inout Path, radius: CGFloat) {
        let rect = CGRect(x: innerRect.maxX - radius, y: innerRect.maxY - radius, width: radius, height: radius)
        let center = CGPoint(x: innerRect.maxX - radius, y: innerRect.maxY - radius)
        path.addRect(rect)
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: innerRect.maxY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true,
        )
        path.closeSubpath()
    }
}

private struct WindowTabStripView: View {
    let strip: WindowTabStripViewModel
    let drawsChrome: Bool

    private struct PendingReorderDrop: Equatable {
        let windowId: UInt32
        let sourceIndex: Int
        let targetIndex: Int
        let orderBeforeDrop: [UInt32]
    }

    @State private var draggingTabId: UInt32? = nil
    @State private var hoveredTabId: UInt32? = nil
    @State private var dragTranslationX: CGFloat = 0
    @State private var hasCommittedToDetach = false
    @State private var pendingReorderDrop: PendingReorderDrop? = nil
    @State private var tabScrollContentMinX: CGFloat = 0
    @Namespace private var tabFeedbackNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            tabStripBody(
                stripWidth: max(proxy.size.width, 0),
                stripHeight: max(proxy.size.height, 0),
            )
        }
    }

    private func tabStripBody(stripWidth: CGFloat, stripHeight: CGFloat) -> some View {
        let tabOrder = strip.tabs.map(\.windowId)
        let tabIndicesById = tabIndexLookup(for: strip.tabs)
        let count = max(strip.tabs.count, 1)
        let tabWidth = windowTabStripTabWidth(stripWidth: stripWidth, count: count)
        let itemHeight = max(stripHeight - 4, 18)
        let effectiveTabWidth = tabWidth + windowTabStripTabSpacing
        let tabContentWidth = CGFloat(strip.tabs.count) * tabWidth
            + CGFloat(max(strip.tabs.count - 1, 0)) * windowTabStripTabSpacing
            + windowTabStripContentHorizontalPadding * 2
        let shouldFadeTabScroll = tabContentWidth > windowTabStripAvailableTabsWidth(stripWidth: stripWidth) + 1
        let scrollCoordinateSpaceName = "window-tab-strip-scroll-\(strip.id.hashValue)"
        let leadingFadeWidth = windowTabLeadingScrollFadeWidth(
            isScrollable: shouldFadeTabScroll,
            contentMinX: tabScrollContentMinX,
            stripWidth: stripWidth,
        )
        let trailingFadeWidth = windowTabTrailingScrollFadeWidth(
            isScrollable: shouldFadeTabScroll,
            stripWidth: stripWidth,
        )
        let activeWindowId = strip.tabs.first(where: \.isActive)?.windowId
        let groupDragWindowId = activeWindowId ?? strip.tabs.first?.windowId
        let stripCornerRadius = strip.activeWindowCornerRadius
        let topInnerCornerRadius = windowTabGroupTopInnerCornerRadius(stripCornerRadius)
        let outerTopRadius = windowTabGroupOuterCornerRadius(innerCornerRadius: topInnerCornerRadius)
        let tabStripShape = windowTabStripShape(outerTopRadius: outerTopRadius)

        let draggingIndex = draggingTabId.flatMap { tabIndicesById[$0] }
        let targetIndex: Int? = draggingIndex.map { srcIdx in
            let delta = Int(round(dragTranslationX / effectiveTabWidth))
            return max(0, min(srcIdx + delta, strip.tabs.count - 1))
        }

        return HStack(spacing: 0) {
            WindowTabGroupHandleView(
                windowId: groupDragWindowId,
                workspaceName: strip.workspaceName
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: windowTabStripTabSpacing) {
                    let tabs = strip.tabs
                    ForEach(tabs) { tab in
                        WindowTabItemView(
                            tab: tab,
                            width: tabWidth,
                            height: itemHeight,
                            isDragSource: draggingTabId == tab.windowId,
                            isHovered: hoveredTabId == tab.windowId,
                            feedbackNamespace: tabFeedbackNamespace
                        )
                        .offset(x: tabVisualOffset(
                            for: tab,
                            draggingIndex: draggingIndex,
                            targetIndex: targetIndex,
                            effectiveTabWidth: effectiveTabWidth,
                            currentOrder: tabOrder,
                            tabIndicesById: tabIndicesById,
                        ))
                        .zIndex(draggingTabId == tab.windowId ? 1 : 0)
                        .shadow(
                            color: draggingTabId == tab.windowId ? Color.black.opacity(0.12) : Color.clear,
                            radius: draggingTabId == tab.windowId ? 6 : 0,
                            y: draggingTabId == tab.windowId ? 2 : 0,
                        )
                        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: targetIndex)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    if shouldPromoteTabStripDragToGroup(windowId: tab.windowId) {
                                        draggingTabId = nil
                                        hoveredTabId = nil
                                        dragTranslationX = 0
                                        hasCommittedToDetach = false
                                        updateMoveFromTabStrip(tab.windowId)
                                        return
                                    }
                                    if hasCommittedToDetach {
                                        updateDetachedTabFromTabStrip(tab.windowId)
                                        return
                                    }

                                    let dy = value.translation.height

                                    // If vertical drag exceeds threshold, commit to detach
                                    if abs(dy) > tabReorderVerticalEscapeThreshold, strip.tabs.count > 1 {
                                        hasCommittedToDetach = true
                                        draggingTabId = nil
                                        hoveredTabId = nil
                                        dragTranslationX = 0
                                        updateDetachedTabFromTabStrip(tab.windowId)
                                        return
                                    }

                                    draggingTabId = tab.windowId
                                    hoveredTabId = nil
                                    dragTranslationX = value.translation.width
                                }
                                .onEnded { _ in
                                    if shouldContinueCurrentGroupDrag(windowId: tab.windowId) {
                                        finishMoveFromTabStrip()
                                    } else if hasCommittedToDetach {
                                        hasCommittedToDetach = false
                                        Task { @MainActor in
                                            try? await resetManipulatedWithMouseIfPossible()
                                        }
                                    } else if let srcIdx = draggingIndex, let tgtIdx = targetIndex, srcIdx != tgtIdx {
                                        settleReorderedTab(
                                            windowId: tab.windowId,
                                            sourceIndex: srcIdx,
                                            targetIndex: tgtIdx,
                                            orderBeforeDrop: tabOrder,
                                        )
                                        reorderTabInStrip(tab.windowId, toIndex: tgtIdx)
                                        return
                                    }
                                    draggingTabId = nil
                                    hoveredTabId = nil
                                    dragTranslationX = 0
                                },
                        )
                        .onHover { hovering in
                            updateHoveredTab(tab.windowId, hovering: hovering)
                        }
                    }
                }
                .padding(.horizontal, windowTabStripContentHorizontalPadding)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: WindowTabStripScrollContentMinXPreferenceKey.self,
                            value: proxy.frame(in: .named(scrollCoordinateSpaceName)).minX,
                        )
                    }
                }
            }
            .coordinateSpace(name: scrollCoordinateSpaceName)
            .onPreferenceChange(WindowTabStripScrollContentMinXPreferenceKey.self) { nextMinX in
                guard abs(tabScrollContentMinX - nextMinX) > 0.5 else { return }
                tabScrollContentMinX = nextMinX
            }
            .mask {
                WindowTabStripScrollFadeMask(
                    leadingFadeWidth: leadingFadeWidth,
                    trailingFadeWidth: trailingFadeWidth,
                )
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in
                        guard let windowId = groupDragWindowId,
                              shouldAllowTabStripChromeGroupDrag(windowId: windowId)
                        else { return }
                        updateMoveFromTabStrip(windowId)
                    }
                    .onEnded { _ in
                        guard let windowId = groupDragWindowId,
                              shouldContinueCurrentGroupDrag(windowId: windowId)
                        else { return }
                        finishMoveFromTabStrip()
                    },
            )

            WindowTabGroupHandleView(
                windowId: groupDragWindowId,
                workspaceName: strip.workspaceName
            )
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(width: stripWidth, height: stripHeight)
        .background {
            if drawsChrome {
                tabStripShape
                    .fill(mattePanelFill)
                tabStripShape
                    .strokeBorder(mattePanelBorder, lineWidth: windowTabGroupFrameStrokeWidth)
            }
        }
        .clipShape(tabStripShape)
        .animation(reduceMotion ? windowTabReducedMotionAnimation : windowTabPillAnimation, value: hoveredTabId)
        .animation(reduceMotion ? windowTabReducedMotionAnimation : windowTabPillAnimation, value: activeWindowId)
        .onChange(of: tabOrder) { newOrder in
            clearPendingReorderDropIfModelApplied(currentOrder: newOrder)
        }
    }

    private func tabIndexLookup(for tabs: [WindowTabItemViewModel]) -> [UInt32: Int] {
        var result: [UInt32: Int] = [:]
        result.reserveCapacity(tabs.count)
        for (index, tab) in tabs.enumerated() {
            result[tab.windowId] = index
        }
        return result
    }

    private func windowTabStripShape(outerTopRadius: CGFloat) -> WindowTabDropOutlineShape {
        WindowTabDropOutlineShape(cornerRadii: PreviewCornerRadii(
            topLeft: outerTopRadius,
            topRight: outerTopRadius,
            bottomRight: 0,
            bottomLeft: 0
        ))
    }

    private func updateHoveredTab(_ windowId: UInt32, hovering: Bool) {
        guard draggingTabId == nil, !hasCommittedToDetach else {
            hoveredTabId = nil
            return
        }
        if hovering {
            hoveredTabId = windowId
        } else if hoveredTabId == windowId {
            hoveredTabId = nil
        }
    }

    private func tabVisualOffset(
        for tab: WindowTabItemViewModel,
        draggingIndex: Int?,
        targetIndex: Int?,
        effectiveTabWidth: CGFloat,
        currentOrder: [UInt32],
        tabIndicesById: [UInt32: Int],
    ) -> CGFloat {
        if let pendingReorderDrop, pendingReorderDrop.orderBeforeDrop == currentOrder {
            if tab.windowId == pendingReorderDrop.windowId {
                return CGFloat(pendingReorderDrop.targetIndex - pendingReorderDrop.sourceIndex) * effectiveTabWidth
            }
            guard let tabIndex = tabIndicesById[tab.windowId] else { return 0 }
            return tabShiftOffset(
                tabIndex: tabIndex,
                sourceIndex: pendingReorderDrop.sourceIndex,
                targetIndex: pendingReorderDrop.targetIndex,
                effectiveTabWidth: effectiveTabWidth,
            )
        }

        guard let draggingIndex, let targetIndex else {
            // Dragged tab follows cursor 1:1
            if tab.windowId == draggingTabId {
                return dragTranslationX
            }
            return 0
        }

        // The dragged tab follows the cursor directly
        if tab.windowId == draggingTabId {
            return dragTranslationX
        }

        guard let tabIndex = tabIndicesById[tab.windowId] else { return 0 }
        return tabShiftOffset(
            tabIndex: tabIndex,
            sourceIndex: draggingIndex,
            targetIndex: targetIndex,
            effectiveTabWidth: effectiveTabWidth,
        )
    }

    private func tabShiftOffset(
        tabIndex: Int,
        sourceIndex: Int,
        targetIndex: Int,
        effectiveTabWidth: CGFloat,
    ) -> CGFloat {
        // Tabs between source and target shift to make room
        if sourceIndex < targetIndex {
            // Dragging right: tabs in (source, target] shift one slot left
            if tabIndex > sourceIndex, tabIndex <= targetIndex {
                return -effectiveTabWidth
            }
        } else if sourceIndex > targetIndex {
            // Dragging left: tabs in [target, source) shift one slot right
            if tabIndex >= targetIndex, tabIndex < sourceIndex {
                return effectiveTabWidth
            }
        }

        return 0
    }

    private func settleReorderedTab(
        windowId: UInt32,
        sourceIndex: Int,
        targetIndex: Int,
        orderBeforeDrop: [UInt32],
    ) {
        pendingReorderDrop = PendingReorderDrop(
            windowId: windowId,
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            orderBeforeDrop: orderBeforeDrop,
        )
        draggingTabId = nil
        hoveredTabId = nil
        dragTranslationX = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + windowTabReorderDropClearDelay) {
            guard pendingReorderDrop?.windowId == windowId else { return }
            pendingReorderDrop = nil
        }
    }

    private func clearPendingReorderDropIfModelApplied(currentOrder: [UInt32]) {
        guard let pendingReorderDrop else { return }
        guard pendingReorderDrop.orderBeforeDrop != currentOrder else { return }
        self.pendingReorderDrop = nil
    }

    private func focusTabStripChrome(windowId: UInt32?) {
        guard let windowId, !isWindowTabStripDragInProgress() else { return }
        focusWindowFromTabStripClick(windowId, fallbackWorkspace: strip.workspaceName)
    }
}

private struct WindowTabStripScrollFadeMask: View {
    let leadingFadeWidth: CGFloat
    let trailingFadeWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let leadingFade = min(leadingFadeWidth, proxy.size.width / 2)
            let trailingFade = min(trailingFadeWidth, proxy.size.width / 2)
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing,
                )
                .frame(width: leadingFade)

                Rectangle()
                    .fill(Color.black)

                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing,
                )
                .frame(width: trailingFade)
            }
        }
    }
}

private struct WindowTabStripScrollContentMinXPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct WindowTabGroupHandleView: View {
    let windowId: UInt32?
    let workspaceName: String

    var body: some View {
        Button {
            guard let windowId, !isWindowTabStripDragInProgress() else { return }
            focusWindowFromTabStripClick(windowId, fallbackWorkspace: workspaceName)
        } label: {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Focus Tab Group")
        .frame(width: windowTabStripReservedGroupHandleWidth())
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { _ in
                    guard let windowId else { return }
                    updateMoveFromTabStrip(windowId)
                }
                .onEnded { _ in
                    finishMoveFromTabStrip()
                },
        )
    }
}

private struct WindowTabOcclusionMask: Shape {
    let panelFrame: CGRect
    let occludingScreenFrames: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        for localRect in windowTabLocalOcclusionRects(
            panelFrame: panelFrame,
            occludingScreenFrames: occludingScreenFrames,
        ) {
            path.addRect(localRect)
        }
        return path
    }
}

private extension View {
    func windowTabOcclusionMasked(panelFrame: CGRect, occludingScreenFrames: [CGRect]) -> some View {
        mask(
            WindowTabOcclusionMask(
                panelFrame: panelFrame,
                occludingScreenFrames: occludingScreenFrames,
            )
            .fill(style: FillStyle(eoFill: true))
        )
    }
}

// MARK: - Tab Item View

private struct WindowTabItemView: View {
    let tab: WindowTabItemViewModel
    let width: CGFloat
    let height: CGFloat
    let isDragSource: Bool
    let isHovered: Bool
    let feedbackNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let iconSize = min(max(height - 14, 14), 18)
        let textWidth = max(width - iconSize - 34, 36)

        ZStack {
            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .fill(baseTabFill)
                .padding(.vertical, 2)

            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .fill(feedbackFill)
                .opacity(feedbackOpacity)
                .padding(.vertical, 2)
                .matchedGeometryEffect(id: feedbackId, in: feedbackNamespace)
                .allowsHitTesting(false)

            if isHovered, !tab.isActive {
                RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    .padding(.vertical, 2)
                    .allowsHitTesting(false)
            }

            Button {
                focusWindowFromTabStripClick(tab.windowId, fallbackWorkspace: tab.workspaceName)
            } label: {
                HStack(spacing: 8) {
                    appIcon(size: iconSize)

                    Text(tab.title)
                        .font(.system(size: 12, weight: tab.isActive ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .allowsTightening(false)
                        .foregroundStyle(foregroundColor)
                        .frame(width: textWidth, alignment: .leading)
                        .clipped()

                    Spacer(minLength: 0)
                }
                    .padding(.horizontal, 12)
                    .frame(width: width, height: height, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: width, height: height)

        }
        .frame(width: width, height: height)
        .clipped()
        .opacity(isDragSource ? 0.55 : 1.0)
        .scaleEffect(isDragSource ? 1.02 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDragSource)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove Tab From Stack") {
                removeWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
            }
        }
    }

    private var feedbackId: String {
        isHovered ? "hover-pill" : "active-pill-\(tab.windowId)"
    }

    private var tabIconText: String {
        tab.appName.first.map { String($0).uppercased() } ?? "W"
    }

    @ViewBuilder
    private func appIcon(size: CGFloat) -> some View {
        if let icon = appIconImage(bundleIdentifier: tab.appBundleId, bundlePath: tab.appBundlePath) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size, alignment: .center)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Text(tabIconText)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(tab.isActive ? 0.86 : 0.62))
                .frame(width: size, height: size, alignment: .center)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(tab.isActive ? 0.22 : 0.14))
                }
                .accessibilityHidden(true)
        }
    }

    private var baseTabFill: Color {
        tab.isActive ? Color.white.opacity(0.055) : Color.white.opacity(0.030)
    }

    private var feedbackFill: Color {
        if isHovered {
            return Color.white.opacity(tab.isActive ? 0.12 : 0.08)
        }
        return tab.isActive ? Color.white.opacity(0.08) : Color.clear
    }

    private var feedbackOpacity: Double {
        isHovered || tab.isActive ? 1 : 0
    }

    private var foregroundColor: Color {
        if tab.isActive { return Color.white.opacity(0.95) }
        if isDragSource { return Color.white.opacity(0.80) }
        return isHovered ? Color.white.opacity(0.82) : Color.white.opacity(0.58)
    }
}

private struct PreviewCornerRadii {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat

    static func uniform(_ radius: CGFloat) -> PreviewCornerRadii {
        PreviewCornerRadii(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
    }
}

private struct WindowTabDropOutlineShape: InsettableShape {
    var cornerRadii: PreviewCornerRadii
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(cornerRadii.topLeft, cornerRadii.topRight),
                AnimatablePair(cornerRadii.bottomRight, cornerRadii.bottomLeft)
            )
        }
        set {
            cornerRadii = PreviewCornerRadii(
                topLeft: newValue.first.first,
                topRight: newValue.first.second,
                bottomRight: newValue.second.first,
                bottomLeft: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard !insetRect.isNull, insetRect.width > 0, insetRect.height > 0 else { return Path() }

        let maxRadius = min(insetRect.width, insetRect.height) / 2
        let tl = min(cornerRadii.topLeft, maxRadius)
        let tr = min(cornerRadii.topRight, maxRadius)
        let br = min(cornerRadii.bottomRight, maxRadius)
        let bl = min(cornerRadii.bottomLeft, maxRadius)

        var path = Path()
        path.move(to: CGPoint(x: insetRect.minX + tl, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX - tr, y: insetRect.minY))
        if tr > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.maxX - tr, y: insetRect.minY + tr),
                radius: tr,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false,
            )
        }
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - br))
        if br > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.maxX - br, y: insetRect.maxY - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false,
            )
        }
        path.addLine(to: CGPoint(x: insetRect.minX + bl, y: insetRect.maxY))
        if bl > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.minX + bl, y: insetRect.maxY - bl),
                radius: bl,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false,
            )
        }
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY + tl))
        if tl > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.minX + tl, y: insetRect.minY + tl),
                radius: tl,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false,
            )
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> WindowTabDropOutlineShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

extension CGRect {
    func alignedToBackingPixels() -> CGRect {
        let scale = (NSScreen.screens
            .max(by: { $0.frame.intersection(self).area < $1.frame.intersection(self).area })?
            .backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        let alignedMinX = (minX * scale).rounded() / scale
        let alignedMinY = (minY * scale).rounded() / scale
        let alignedMaxX = (maxX * scale).rounded() / scale
        let alignedMaxY = (maxY * scale).rounded() / scale
        return CGRect(
            x: alignedMinX,
            y: alignedMinY,
            width: max(alignedMaxX - alignedMinX, 0),
            height: max(alignedMaxY - alignedMinY, 0),
        )
    }

    fileprivate var area: CGFloat {
        isNull ? 0 : width * height
    }
}
