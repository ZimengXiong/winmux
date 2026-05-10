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
