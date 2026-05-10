import AppKit
import Common

struct WindowResizePreviewItem: Identifiable, Equatable {
    let id: UInt32
    let frame: CGRect
    let appName: String
    let icons: [WindowResizePreviewIcon]
    let isTabGroup: Bool
    let drawsFrameOnly: Bool
    let frameOnlyHeaderHeight: CGFloat
}

struct WindowResizePreviewIcon: Hashable {
    let appName: String
    let appBundleId: String?
    let appBundlePath: String?
}

@MainActor
func windowResizePreviewItems(
    in workspace: Workspace,
    weightMap: WindowResizePreviewWeightMap,
    excludingActiveWindowId activeWindowId: UInt32?,
) -> [WindowResizePreviewItem] {
    guard !workspace.isEffectivelyEmpty else { return [] }
    let rect = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
    let context = WindowResizePreviewLayoutContext(workspace: workspace, weightMap: weightMap)
    var items = windowResizePreviewItems(
        node: workspace.rootTilingContainer,
        point: rect.topLeftCorner,
        width: rect.width,
        height: rect.height - 1,
        virtual: rect,
        context: context,
        activeWindowId: activeWindowId,
    )
    for window in workspace.floatingWindows where window.isBound {
        guard window.windowId != activeWindowId else { continue }
        guard let rect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect,
              rect.width > 0,
              rect.height > 0
        else { continue }
        items.append(WindowResizePreviewItem(window: window, rect: rect))
    }
    return items
}

@MainActor
private func windowResizePreviewItems(
    node: TreeNode,
    point: CGPoint,
    width: CGFloat,
    height: CGFloat,
    virtual: Rect,
    context: WindowResizePreviewLayoutContext,
    activeWindowId: UInt32?,
) -> [WindowResizePreviewItem] {
    let physicalRect = Rect(
        topLeftX: point.x,
        topLeftY: point.y,
        width: max(width, 0),
        height: max(height, 0),
    )
    switch node.nodeCases {
        case .workspace(let workspace):
            return windowResizePreviewItems(
                node: workspace.rootTilingContainer,
                point: point,
                width: width,
                height: height,
                virtual: virtual,
                context: context,
                activeWindowId: activeWindowId,
            )
        case .window(let window):
            guard window.windowId != activeWindowId else { return [] }
            guard physicalRect.width > 0, physicalRect.height > 0 else { return [] }
            return [WindowResizePreviewItem(window: window, rect: physicalRect)]
        case .tilingContainer(let container):
            if container.usesWindowTabBehavior {
                if let activeWindowId, container.containsLeafWindow(withId: activeWindowId) {
                    return []
                }
                guard physicalRect.width > 0, physicalRect.height > 0 else { return [] }
                return [WindowResizePreviewItem(tabGroup: container, rect: physicalRect)]
            }
            switch container.layout {
                case .tiles:
                    return windowResizePreviewTileItems(
                        container: container,
                        point: point,
                        width: width,
                        height: height,
                        virtual: virtual,
                        context: context,
                        activeWindowId: activeWindowId,
                    )
                case .tabGroup:
                    return windowResizePreviewTabGroupItems(
                        container: container,
                        point: point,
                        width: width,
                        height: height,
                        virtual: virtual,
                        context: context,
                        activeWindowId: activeWindowId,
                    )
            }
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return []
    }
}

@MainActor
private func windowResizePreviewTileItems(
    container: TilingContainer,
    point: CGPoint,
    width: CGFloat,
    height: CGFloat,
    virtual: Rect,
    context: WindowResizePreviewLayoutContext,
    activeWindowId: UInt32?,
) -> [WindowResizePreviewItem] {
    guard !container.children.isEmpty else { return [] }

    var items: [WindowResizePreviewItem] = []
    var point = point
    var virtualPoint = virtual.topLeftCorner
    let orientation = container.orientation
    let availableDimension = orientation == .h ? width : height
    let totalWeight = container.children.reduce(CGFloat(0)) { partial, child in
        partial + context.weight(for: child, orientation: orientation)
    }
    guard let delta = (availableDimension - totalWeight).div(container.children.count) else { return [] }

    let rawGap = CGFloat(context.resolvedGaps.inner.get(orientation))
    let lastIndex = container.children.indices.last
    for (index, child) in container.children.enumerated() {
        let adjustedWeight = context.weight(for: child, orientation: orientation) + delta
        let gap = rawGap - (index == 0 ? rawGap / 2 : 0) - (index == lastIndex ? rawGap / 2 : 0)
        let childPoint = index == 0 ? point : point.addingOffset(orientation, rawGap / 2)
        let childWidth = orientation == .h ? max(adjustedWeight - gap, 0) : max(width, 0)
        let childHeight = orientation == .v ? max(adjustedWeight - gap, 0) : max(height, 0)
        let childVirtual = Rect(
            topLeftX: virtualPoint.x,
            topLeftY: virtualPoint.y,
            width: orientation == .h ? max(adjustedWeight, 0) : max(width, 0),
            height: orientation == .v ? max(adjustedWeight, 0) : max(height, 0),
        )
        items += windowResizePreviewItems(
            node: child,
            point: childPoint,
            width: childWidth,
            height: childHeight,
            virtual: childVirtual,
            context: context,
            activeWindowId: activeWindowId,
        )
        virtualPoint = orientation == .h
            ? virtualPoint.addingXOffset(adjustedWeight)
            : virtualPoint.addingYOffset(adjustedWeight)
        point = orientation == .h
            ? point.addingXOffset(adjustedWeight)
            : point.addingYOffset(adjustedWeight)
    }
    return items
}

@MainActor
private func windowResizePreviewTabGroupItems(
    container: TilingContainer,
    point: CGPoint,
    width: CGFloat,
    height: CGFloat,
    virtual: Rect,
    context: WindowResizePreviewLayoutContext,
    activeWindowId: UInt32?,
) -> [WindowResizePreviewItem] {
    if container.usesWindowTabBehavior {
        if let activeWindowId, container.containsLeafWindow(withId: activeWindowId) {
            return []
        }
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: max(width, 0), height: max(height, 0))
        guard physicalRect.width > 0, physicalRect.height > 0 else { return [] }
        return [WindowResizePreviewItem(tabGroup: container, rect: physicalRect)]
    }

    guard let mruIndex = container.mostRecentChild?.ownIndex else { return [] }
    var items: [WindowResizePreviewItem] = []
    for (index, child) in container.children.enumerated() {
        let padding = CGFloat(config.tabGroupPadding)
        let (leadingPadding, trailingPadding): (CGFloat, CGFloat) = switch index {
            case 0 where container.children.count == 1: (0, 0)
            case 0:                                    (0, padding)
            case container.children.indices.last:       (padding, 0)
            case mruIndex - 1:                         (0, 2 * padding)
            case mruIndex + 1:                         (2 * padding, 0)
            default:                                   (padding, padding)
        }
        switch container.orientation {
            case .h:
                items += windowResizePreviewItems(
                    node: child,
                    point: point + CGPoint(x: leadingPadding, y: 0),
                    width: max(width - trailingPadding - leadingPadding, 0),
                    height: height,
                    virtual: virtual,
                    context: context,
                    activeWindowId: activeWindowId,
                )
            case .v:
                items += windowResizePreviewItems(
                    node: child,
                    point: point + CGPoint(x: 0, y: leadingPadding),
                    width: width,
                    height: max(height - leadingPadding - trailingPadding, 0),
                    virtual: virtual,
                    context: context,
                    activeWindowId: activeWindowId,
                )
        }
    }
    return items
}

private struct WindowResizePreviewLayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps
    let weightMap: WindowResizePreviewWeightMap

    @MainActor
    init(workspace: Workspace, weightMap: WindowResizePreviewWeightMap) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
        self.weightMap = weightMap
    }

    @MainActor
    func weight(for node: TreeNode, orientation: Orientation) -> CGFloat {
        weightMap.weight(for: node, orientation: orientation)
    }
}

private extension WindowResizePreviewItem {
    @MainActor
    init(window: Window, rect: Rect, drawsFrameOnly: Bool = false) {
        let icon = WindowResizePreviewIcon(window: window)
        self.init(
            id: window.windowId,
            frame: rect.toAppKitScreenRect.alignedToBackingPixels(),
            appName: window.app.name ?? window.app.rawAppBundleId ?? "Window",
            icons: [icon],
            isTabGroup: false,
            drawsFrameOnly: drawsFrameOnly,
            frameOnlyHeaderHeight: 0,
        )
    }

    @MainActor
    init(tabGroup container: TilingContainer, rect: Rect, drawsFrameOnly: Bool = false) {
        let windows = container.childrenByMostRecentUse.compactMap(\.tabRepresentativeWindow)
        let representative = windows.first ?? container.tabRepresentativeWindow
        let icons = windows.map(WindowResizePreviewIcon.init(window:))
        let headerHeight = drawsFrameOnly ? windowTabBarRect(forGroupFrameRect: rect).height : 0
        self.init(
            id: representative?.windowId ?? UInt32(abs(ObjectIdentifier(container).hashValue) % Int(UInt32.max)),
            frame: rect.toAppKitScreenRect.alignedToBackingPixels(),
            appName: representative?.app.name ?? representative?.app.rawAppBundleId ?? "Tab Group",
            icons: icons,
            isTabGroup: true,
            drawsFrameOnly: drawsFrameOnly,
            frameOnlyHeaderHeight: headerHeight,
        )
    }
}

@MainActor
func windowDragSourcePreviewItem(window: Window, subject: WindowDragSubject, frame: Rect) -> WindowResizePreviewItem? {
    guard frame.width > 0, frame.height > 0 else { return nil }
    if subject == .group,
       let tabGroup = window.moveNode as? TilingContainer,
       tabGroup.usesWindowTabBehavior
    {
        return WindowResizePreviewItem(tabGroup: tabGroup, rect: frame, drawsFrameOnly: true)
    }
    return WindowResizePreviewItem(window: window, rect: frame)
}

@MainActor
func windowResizeSourceTabGroupPreviewItem(window: Window, activeWindowRect: Rect) -> WindowResizePreviewItem? {
    guard let tabGroup = window.nearestWindowTabGroup,
          tabGroup.usesWindowTabBehavior,
          tabGroup.tabActiveWindow == window
    else { return nil }
    let groupFrame = windowTabGroupFrameRect(forActiveWindowContentRect: activeWindowRect)
    guard groupFrame.width > 0, groupFrame.height > 0 else { return nil }
    return WindowResizePreviewItem(tabGroup: tabGroup, rect: groupFrame, drawsFrameOnly: true)
}

private extension WindowResizePreviewIcon {
    @MainActor
    init(window: Window) {
        self.init(
            appName: window.app.name ?? window.app.rawAppBundleId ?? "Window",
            appBundleId: window.app.rawAppBundleId,
            appBundlePath: window.app.bundlePath,
        )
    }
}

func windowResizePreviewAllScreensFrame() -> CGRect? {
    guard let first = NSScreen.screens.first?.frame else { return nil }
    let union = NSScreen.screens.dropFirst().reduce(first) { $0.union($1.frame) }
    return union.insetBy(dx: -128, dy: -128)
}

@MainActor
final class WindowResizePreviewPanel: NSPanelHud {
    static let shared = WindowResizePreviewPanel()

    private let compositorView = WindowResizePreviewCompositorView()
    private var pendingHide: DispatchWorkItem? = nil
    private var stableFrame: CGRect? = nil

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier("WinMux.resizePreview")
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        backgroundColor = .clear
        applyWinMuxLayer(.overlay)

        compositorView.frame = contentView?.bounds ?? .zero
        compositorView.autoresizingMask = [.width, .height]
        contentView = compositorView
    }

    func beginStableFrame(_ frame: CGRect) {
        stableFrame = frame.alignedToBackingPixels()
    }

    func endStableFrame() {
        stableFrame = nil
    }

    func show(_ screenItems: [WindowResizePreviewItem]) {
        pendingHide?.cancel()
        pendingHide = nil
        guard let panelFrame = stableFrame ?? windowResizePreviewPanelFrame(for: screenItems) else {
            hide()
            return
        }

        let alignedPanelFrame = panelFrame.alignedToBackingPixels()
        let localItems = screenItems.map { $0.localItem(in: alignedPanelFrame) }
        if frame.size == alignedPanelFrame.size {
            setFrameOrigin(alignedPanelFrame.origin)
        } else {
            setFrame(alignedPanelFrame, display: false, animate: false)
        }
        compositorView.update(localItems)
        if !isVisible {
            orderFrontRegardless()
        }
    }

    func hide(after delay: TimeInterval = 0) {
        pendingHide?.cancel()
        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            self.compositorView.clear()
            self.orderOut(nil)
        }
        pendingHide = hideWorkItem
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: hideWorkItem)
        } else {
            hideWorkItem.perform()
        }
    }
}

private struct WindowResizePreviewLocalItem: Identifiable, Equatable {
    let id: UInt32
    let frame: CGRect
    let appName: String
    let icons: [WindowResizePreviewIcon]
    let isTabGroup: Bool
    let drawsFrameOnly: Bool
    let frameOnlyHeaderHeight: CGFloat
}

@MainActor
private final class WindowResizePreviewCompositorView: NSView {
    private var itemLayers: [UInt32: WindowResizePreviewItemLayer] = [:]
    private var iconCache: [WindowResizePreviewIcon: CGImage] = [:]

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let backingLayer = CALayer()
        backingLayer.masksToBounds = false
        backingLayer.isGeometryFlipped = true
        layer = backingLayer
        disableResizePreviewLayerActions(backingLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ items: [WindowResizePreviewLocalItem]) {
        let visibleIds = Set(items.map(\.id))
        var appearingLayers: [WindowResizePreviewItemLayer] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for staleId in itemLayers.keys where !visibleIds.contains(staleId) {
            itemLayers[staleId]?.removeFromSuperlayer()
            itemLayers.removeValue(forKey: staleId)
        }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for item in items {
            let isNewLayer = itemLayers[item.id] == nil
            let itemLayer = itemLayers[item.id] ?? WindowResizePreviewItemLayer()
            if isNewLayer {
                itemLayer.opacity = 0
                itemLayers[item.id] = itemLayer
                layer?.addSublayer(itemLayer)
                appearingLayers.append(itemLayer)
            }
            itemLayer.update(item, scale: scale, iconResolver: resolvedIconImage)
        }
        CATransaction.commit()
        appearingLayers.forEach { $0.animateAppear() }
        isHidden = items.isEmpty
    }

    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for itemLayer in itemLayers.values {
            itemLayer.removeFromSuperlayer()
        }
        itemLayers.removeAll()
        isHidden = true
        CATransaction.commit()
    }

    private func resolvedIconImage(_ icon: WindowResizePreviewIcon) -> CGImage? {
        if let cached = iconCache[icon] {
            return cached
        }
        guard let image = appIconImage(bundleIdentifier: icon.appBundleId, bundlePath: icon.appBundlePath) else {
            return nil
        }
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }
        iconCache[icon] = cgImage
        return cgImage
    }
}

private final class WindowResizePreviewItemLayer: CALayer {
    private let surfaceLayer = CAShapeLayer()
    private let topBarLayer = CAShapeLayer()
    private let mockTabStrokeLayer = CAShapeLayer()
    private let strokeLayer = CAShapeLayer()
    private var iconLayers: [CALayer] = []

    override init() {
        super.init()
        masksToBounds = false
        disableResizePreviewLayerActions(self)

        surfaceLayer.fillColor = ResizePreviewPalette.fill
        strokeLayer.fillColor = NSColor.clear.cgColor
        strokeLayer.strokeColor = ResizePreviewPalette.stroke
        strokeLayer.lineWidth = 0.7
        topBarLayer.fillColor = ResizePreviewPalette.tabGroupBar
        mockTabStrokeLayer.fillColor = NSColor.clear.cgColor
        mockTabStrokeLayer.strokeColor = ResizePreviewPalette.sourceMockTabStroke
        mockTabStrokeLayer.lineWidth = 0.7
        [surfaceLayer, topBarLayer, mockTabStrokeLayer, strokeLayer].forEach {
            disableResizePreviewLayerActions($0)
            addSublayer($0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    func animateAppear() {
        removeAnimation(forKey: "resizePreviewAppear")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.12
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        opacity = 1
        add(fade, forKey: "resizePreviewAppear")
    }

    func update(
        _ item: WindowResizePreviewLocalItem,
        scale: CGFloat,
        iconResolver: (WindowResizePreviewIcon) -> CGImage?,
    ) {
        contentsScale = scale
        frame = item.frame
        let localBounds = CGRect(origin: .zero, size: item.frame.size)
        if item.isTabGroup, item.drawsFrameOnly {
            updateFrameOnlyShell(item: item, bounds: localBounds, scale: scale)
            return
        }
        let radius = windowResizePreviewCornerRadius(for: localBounds)
        let path = CGPath(roundedRect: localBounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        surfaceLayer.fillRule = .nonZero
        surfaceLayer.fillColor = ResizePreviewPalette.fill
        surfaceLayer.frame = localBounds
        surfaceLayer.path = path
        surfaceLayer.contentsScale = scale
        mockTabStrokeLayer.isHidden = true
        mockTabStrokeLayer.path = nil
        strokeLayer.strokeColor = ResizePreviewPalette.stroke
        strokeLayer.lineWidth = 0.7
        strokeLayer.frame = localBounds
        strokeLayer.path = path
        strokeLayer.contentsScale = scale
        updateTopBar(item: item, radius: radius, scale: scale)
        updateIcons(item: item, scale: scale, iconResolver: iconResolver)
    }

    private func updateFrameOnlyShell(item: WindowResizePreviewLocalItem, bounds localBounds: CGRect, scale: CGFloat) {
        hideIconLayers()

        let shellPath = windowResizePreviewTabGroupShellPath(
            in: localBounds,
            headerHeight: item.frameOnlyHeaderHeight,
        )
        let mockTabsPath = windowResizePreviewMockTabPillsPath(
            in: localBounds,
            headerHeight: item.frameOnlyHeaderHeight,
            tabCount: item.icons.count,
        )
        surfaceLayer.fillRule = .evenOdd
        surfaceLayer.fillColor = ResizePreviewPalette.sourceFrameFill
        surfaceLayer.frame = localBounds
        surfaceLayer.path = shellPath
        surfaceLayer.contentsScale = scale

        topBarLayer.isHidden = false
        topBarLayer.fillColor = ResizePreviewPalette.sourceMockTabFill
        topBarLayer.frame = localBounds
        topBarLayer.path = mockTabsPath
        topBarLayer.contentsScale = scale

        mockTabStrokeLayer.isHidden = false
        mockTabStrokeLayer.strokeColor = ResizePreviewPalette.sourceMockTabStroke
        mockTabStrokeLayer.lineWidth = 0.7
        mockTabStrokeLayer.frame = localBounds
        mockTabStrokeLayer.path = mockTabsPath
        mockTabStrokeLayer.contentsScale = scale

        strokeLayer.strokeColor = ResizePreviewPalette.sourceFrameStroke
        strokeLayer.lineWidth = 0.8
        strokeLayer.frame = localBounds
        strokeLayer.path = shellPath
        strokeLayer.contentsScale = scale
    }

    private func updateTopBar(item: WindowResizePreviewLocalItem, radius: CGFloat, scale: CGFloat) {
        topBarLayer.isHidden = !item.isTabGroup
        guard item.isTabGroup else {
            topBarLayer.path = nil
            return
        }
        let localBounds = CGRect(origin: .zero, size: item.frame.size)
        let height = min(max(item.frame.height * 0.12, 16), 30)
        let insetBounds = localBounds.insetBy(dx: 4, dy: 4)
        let barRect = CGRect(x: insetBounds.minX, y: insetBounds.minY, width: insetBounds.width, height: height)
        topBarLayer.fillColor = ResizePreviewPalette.tabGroupBar
        topBarLayer.frame = localBounds
        topBarLayer.path = CGPath(
            roundedRect: barRect,
            cornerWidth: max(radius * 0.7, 4),
            cornerHeight: max(radius * 0.7, 4),
            transform: nil,
        )
        topBarLayer.contentsScale = scale
    }

    private func updateIcons(
        item: WindowResizePreviewLocalItem,
        scale: CGFloat,
        iconResolver: (WindowResizePreviewIcon) -> CGImage?,
    ) {
        let visibleIcons = item.isTabGroup ? item.icons : Array(item.icons.prefix(1))
        let iconCount = max(visibleIcons.count, 1)
        while iconLayers.count < iconCount {
            let iconLayer = CALayer()
            iconLayer.masksToBounds = true
            iconLayer.contentsGravity = .resizeAspect
            disableResizePreviewLayerActions(iconLayer)
            addSublayer(iconLayer)
            iconLayers.append(iconLayer)
        }
        for extraIndex in iconCount..<iconLayers.count {
            iconLayers[extraIndex].isHidden = true
        }

        let iconSize = min(max(min(item.frame.width, item.frame.height) * 0.18, 32), 72)
        for index in 0..<iconCount {
            let iconLayer = iconLayers[index]
            iconLayer.isHidden = false
            iconLayer.contentsScale = scale
            iconLayer.cornerRadius = max(iconSize * 0.18, 6)
            iconLayer.backgroundColor = ResizePreviewPalette.fallbackIconFill
            let icon = visibleIcons.getOrNil(atIndex: index)
            iconLayer.contents = icon.flatMap(iconResolver)
            if iconLayer.contents == nil {
                iconLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
                let textLayer = fallbackTextLayer(text: fallbackLetter(icon: icon, item: item), size: iconSize, scale: scale)
                iconLayer.addSublayer(textLayer)
            } else {
                iconLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            }

            let offset = item.isTabGroup && iconCount > 1
                ? windowResizePreviewStackOffset(index, iconCount: iconCount, size: iconSize)
                : .zero
            let center = CGPoint(
                x: item.frame.width / 2 + offset.width,
                y: item.frame.height / 2 + offset.height,
            )
            iconLayer.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
            iconLayer.position = center
            iconLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(windowResizePreviewStackRotation(index) * Double.pi / 180)))
            iconLayer.zPosition = CGFloat(iconCount - index)
        }
    }

    private func hideIconLayers() {
        for iconLayer in iconLayers {
            iconLayer.isHidden = true
            iconLayer.contents = nil
            iconLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
    }

    private func fallbackTextLayer(text: String, size: CGFloat, scale: CGFloat) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.frame = CGRect(x: 0, y: (size - size * 0.52) / 2 - 1, width: size, height: size * 0.58)
        textLayer.string = text
        textLayer.alignmentMode = .center
        textLayer.contentsScale = scale
        textLayer.foregroundColor = NSColor.white.withAlphaComponent(0.82).cgColor
        textLayer.font = NSFont.systemFont(ofSize: size * 0.42, weight: .bold)
        textLayer.fontSize = size * 0.42
        disableResizePreviewLayerActions(textLayer)
        return textLayer
    }

    private func fallbackLetter(icon: WindowResizePreviewIcon?, item: WindowResizePreviewLocalItem) -> String {
        (icon?.appName ?? item.appName).first.map { String($0).uppercased() } ?? "W"
    }
}

private enum ResizePreviewPalette {
    static let fill = mattePanelNSColor.cgColor
    static let stroke = NSColor.white.withAlphaComponent(0.04).cgColor
    static let tabGroupBar = NSColor.white.withAlphaComponent(0.055).cgColor
    static let fallbackIconFill = NSColor.white.withAlphaComponent(0.12).cgColor
    static let sourceFrameFill = mattePanelNSColor.cgColor
    static let sourceFrameStroke = NSColor.white.withAlphaComponent(0.055).cgColor
    static let sourceMockTabFill = NSColor.white.withAlphaComponent(0.085).cgColor
    static let sourceMockTabStroke = NSColor.white.withAlphaComponent(0.075).cgColor
}

private final class ResizePreviewDisabledLayerAction: NSObject, CAAction {
    func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {}
}

private func disableResizePreviewLayerActions(_ layer: CALayer) {
    let action = ResizePreviewDisabledLayerAction()
    layer.actions = [
        "backgroundColor": action,
        "bounds": action,
        "contents": action,
        "cornerRadius": action,
        "frame": action,
        "hidden": action,
        "opacity": action,
        "path": action,
        "position": action,
        "sublayers": action,
        "transform": action,
    ]
}

private struct ResizePreviewCornerRadii {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat

    static func uniform(_ radius: CGFloat) -> ResizePreviewCornerRadii {
        ResizePreviewCornerRadii(
            topLeft: radius,
            topRight: radius,
            bottomRight: radius,
            bottomLeft: radius
        )
    }
}

private func windowResizePreviewTabGroupShellPath(in bounds: CGRect, headerHeight: CGFloat) -> CGPath {
    let path = CGMutablePath()
    guard bounds.width > 0, bounds.height > 0 else { return path }

    let shellInset = min(windowTabGroupShellHorizontalInset(), bounds.width / 2)
    let bottomInset = min(windowTabGroupShellBottomInset(), bounds.height)
    let tabHeight = min(max(headerHeight, 0), bounds.height)
    let contentHeight = max(bounds.height - tabHeight - bottomInset, 0)
    let innerRect = CGRect(
        x: bounds.minX + shellInset,
        y: bounds.minY + tabHeight,
        width: max(bounds.width - shellInset * 2, 0),
        height: contentHeight,
    )
    let appRadius = min(max(min(innerRect.width, innerRect.height) * 0.04, 8), 22)
    let topInnerRadius = min(max(appRadius + shellInset + 14, 30), 40)
    let bottomOuterRadius = appRadius + shellInset

    path.addPath(windowResizePreviewRoundedRectPath(
        in: bounds,
        radii: ResizePreviewCornerRadii(
            topLeft: 12,
            topRight: 12,
            bottomRight: bottomOuterRadius,
            bottomLeft: bottomOuterRadius,
        )
    ))
    if innerRect.width > 0, innerRect.height > 0 {
        path.addPath(windowResizePreviewRoundedRectPath(
            in: innerRect,
            radii: ResizePreviewCornerRadii(
                topLeft: topInnerRadius,
                topRight: topInnerRadius,
                bottomRight: appRadius,
                bottomLeft: appRadius,
            )
        ))
    }
    return path
}

private func windowResizePreviewMockTabPillsPath(in bounds: CGRect, headerHeight: CGFloat, tabCount: Int) -> CGPath {
    let path = CGMutablePath()
    guard bounds.width > 0, bounds.height > 0 else { return path }

    let resolvedHeaderHeight = min(max(headerHeight, 18), bounds.height)
    let horizontalInset = min(windowTabGroupShellHorizontalInset(), bounds.width / 2)
    let handleWidth = windowTabStripReservedGroupHandleWidth()
    let contentPadding = windowTabStripContentPadding()
    let minX = bounds.minX + horizontalInset + handleWidth + contentPadding
    let maxX = bounds.maxX - horizontalInset - handleWidth - contentPadding
    let availableWidth = max(maxX - minX, 0)
    guard availableWidth > 0 else { return path }

    let visibleCount = windowResizePreviewMockTabVisibleCount(
        availableWidth: availableWidth,
        tabCount: tabCount,
        tabWidth: windowTabStripTabWidth(stripWidth: bounds.width, count: max(tabCount, 1)),
    )
    let tabWidth = min(windowTabStripTabWidth(stripWidth: bounds.width, count: max(tabCount, 1)), availableWidth)
    let tabHeight = max(resolvedHeaderHeight - 8, 10)
    let tabY = bounds.minY + (resolvedHeaderHeight - tabHeight) / 2
    var tabX = minX

    for _ in 0..<visibleCount {
        let remainingWidth = maxX - tabX
        guard remainingWidth >= 24 else { break }
        let rect = CGRect(
            x: tabX,
            y: tabY,
            width: min(tabWidth, remainingWidth),
            height: tabHeight,
        )
        let radius = min(12, rect.height / 2)
        path.addPath(windowResizePreviewRoundedRectPath(in: rect, radii: .uniform(radius)))
        tabX += tabWidth + windowResizePreviewMockTabSpacing
    }

    return path
}

private let windowResizePreviewMockTabSpacing: CGFloat = 8

private func windowResizePreviewMockTabVisibleCount(
    availableWidth: CGFloat,
    tabCount: Int,
    tabWidth: CGFloat,
) -> Int {
    let requestedCount = max(tabCount, 1)
    let effectiveWidth = max(tabWidth + windowResizePreviewMockTabSpacing, 1)
    let fittingCount = Int(ceil((availableWidth + windowResizePreviewMockTabSpacing) / effectiveWidth))
    return max(1, min(requestedCount, fittingCount))
}

private func windowResizePreviewCornerRadius(for rect: CGRect) -> CGFloat {
    let minimumDimension = min(rect.width, rect.height)
    guard minimumDimension > 0 else { return 0 }
    return min(min(max(minimumDimension * 0.04, 8), 16), minimumDimension / 2)
}

private func windowResizePreviewRoundedRectPath(in rect: CGRect, radii: ResizePreviewCornerRadii) -> CGPath {
    let path = CGMutablePath()
    guard rect.width > 0, rect.height > 0 else { return path }

    let maxRadius = min(rect.width, rect.height) / 2
    let topLeft = min(radii.topLeft, maxRadius)
    let topRight = min(radii.topRight, maxRadius)
    let bottomRight = min(radii.bottomRight, maxRadius)
    let bottomLeft = min(radii.bottomLeft, maxRadius)

    path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
    if topRight > 0 {
        path.addArc(
            center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
            radius: topRight,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: false,
        )
    }
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
    if bottomRight > 0 {
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
            radius: bottomRight,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: false,
        )
    }
    path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
    if bottomLeft > 0 {
        path.addArc(
            center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
            radius: bottomLeft,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: false,
        )
    }
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
    if topLeft > 0 {
        path.addArc(
            center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
            radius: topLeft,
            startAngle: .pi,
            endAngle: .pi * 1.5,
            clockwise: false,
        )
    }
    path.closeSubpath()
    return path
}

private func windowResizePreviewStackOffset(_ index: Int, iconCount: Int, size: CGFloat) -> CGSize {
    let offsets = [
        CGSize(width: 0, height: -size * 0.08),
        CGSize(width: -size * 0.24, height: size * 0.16),
        CGSize(width: size * 0.24, height: size * 0.18),
        CGSize(width: -size * 0.02, height: size * 0.32),
    ]
    let offset = offsets[min(index, offsets.count - 1)]
    return iconCount == 2 && index == 1 ? CGSize(width: -size * 0.18, height: size * 0.16) : offset
}

private func windowResizePreviewStackRotation(_ index: Int) -> Double {
    let rotations = [-4.0, 7.0, -8.0, 3.0]
    return rotations[min(index, rotations.count - 1)]
}

private extension WindowResizePreviewItem {
    func localItem(in panelFrame: CGRect) -> WindowResizePreviewLocalItem {
        WindowResizePreviewLocalItem(
            id: id,
            frame: CGRect(
                x: frame.minX - panelFrame.minX,
                y: panelFrame.maxY - frame.maxY,
                width: frame.width,
                height: frame.height,
            ),
            appName: appName,
            icons: icons,
            isTabGroup: isTabGroup,
            drawsFrameOnly: drawsFrameOnly,
            frameOnlyHeaderHeight: frameOnlyHeaderHeight,
        )
    }
}

private func windowResizePreviewPanelFrame(for items: [WindowResizePreviewItem]) -> CGRect? {
    guard let firstFrame = items.first?.frame else { return nil }
    let union = items.dropFirst().reduce(firstFrame) { $0.union($1.frame) }
    return union.insetBy(dx: -8, dy: -8)
}
