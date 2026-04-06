import AppKit
import Common

extension Workspace {
    @MainActor
    func layoutWorkspace() async throws {
        if isEffectivelyEmpty { return }
        let rect = workspaceMonitor.visibleRectPaddedByOuterGaps
        let context = LayoutContext(self)
        if let fullscreenWindow = rootTilingContainer.mostRecentWindowRecursive, fullscreenWindow.isFullscreen {
            lastAppliedLayoutPhysicalRect = rect
            lastAppliedLayoutVirtualRect = rect
            rootTilingContainer.lastAppliedLayoutPhysicalRect = rect
            rootTilingContainer.lastAppliedLayoutVirtualRect = rect
            try await hideAllWindowsExcept(fullscreenWindow)
            fullscreenWindow.lastAppliedLayoutVirtualRect = rect
            fullscreenWindow.lastAppliedLayoutPhysicalRect = nil
            fullscreenWindow.layoutFullscreen(context)
            return
        }
        // If monitors are aligned vertically and the monitor below has smaller width, then macOS may not allow the
        // window on the upper monitor to take full width. rect.height - 1 resolves this problem
        // But I also faced this problem in monitors horizontal configuration. ¯\_(ツ)_/¯
        try await layoutRecursive(rect.topLeftCorner, width: rect.width, height: rect.height - 1, virtual: rect, context)
    }
}

extension TreeNode {
    @MainActor
    fileprivate func layoutRecursive(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        switch nodeCases {
            case .workspace(let workspace):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                try await workspace.rootTilingContainer.layoutRecursive(point, width: width, height: height, virtual: virtual, context)
                for window in workspace.children.filterIsInstance(of: Window.self) {
                    window.lastAppliedLayoutPhysicalRect = nil
                    window.lastAppliedLayoutVirtualRect = nil
                    try await window.layoutFloatingWindow(context)
                }
            case .window(let window):
                if window.windowId != currentlyManipulatedWithMouseWindowId || isPinnedDraggedWindow(window.windowId) {
                    let previousPhysicalRect = lastAppliedLayoutPhysicalRect
                    lastAppliedLayoutVirtualRect = virtual
                    if window.isFullscreen && window == context.workspace.rootTilingContainer.mostRecentWindowRecursive {
                        lastAppliedLayoutPhysicalRect = nil
                        window.layoutFullscreen(context)
                    } else {
                        lastAppliedLayoutPhysicalRect = physicalRect
                        window.isFullscreen = false
                        if config.enableWindowManagement &&
                            !canReuseLastAppliedWindowFrame(previousPhysicalRect: previousPhysicalRect, nextPhysicalRect: physicalRect)
                        {
                            window.setAxFrame(point, CGSize(width: width, height: height))
                        }
                    }
                }
            case .tilingContainer(let container):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                if container.usesWindowTabBehavior {
                    debugFocusLog("layoutRecursive tabContainer=\(ObjectIdentifier(container)) physicalRect=\(physicalRect) virtualRect=\(virtual)")
                }
                switch container.layout {
                    case .tiles:
                        try await container.layoutTiles(point, width: width, height: height, virtual: virtual, context)
                    case .accordion:
                        try await container.layoutAccordion(point, width: width, height: height, virtual: virtual, context)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return // Nothing to do for weirdos
        }
    }
}

private func canReuseLastAppliedWindowFrame(previousPhysicalRect: Rect?, nextPhysicalRect: Rect) -> Bool {
    guard refreshSessionEvent?.canReuseLastAppliedWindowFrames == true else { return false }
    guard let previousPhysicalRect else { return false }
    return previousPhysicalRect.topLeftX == nextPhysicalRect.topLeftX &&
        previousPhysicalRect.topLeftY == nextPhysicalRect.topLeftY &&
        previousPhysicalRect.width == nextPhysicalRect.width &&
        previousPhysicalRect.height == nextPhysicalRect.height
}

private struct LayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps

    @MainActor
    init(_ workspace: Workspace) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
    }
}

extension Window {
    @MainActor
    fileprivate func layoutFloatingWindow(_ context: LayoutContext) async throws {
        if !config.enableWindowManagement {
            if isFullscreen {
                layoutFullscreen(context)
                isFullscreen = false
            }
            return
        }
        let workspace = context.workspace
        let windowRect = try await getAxRect() // Probably not idempotent
        let currentMonitor = windowRect?.center.monitorApproximation
        if let currentMonitor, let windowRect, workspace != currentMonitor.activeWorkspace {
            let windowTopLeftCorner = windowRect.topLeftCorner
            let xProportion = (windowTopLeftCorner.x - currentMonitor.visibleRect.topLeftX) / currentMonitor.visibleRect.width
            let yProportion = (windowTopLeftCorner.y - currentMonitor.visibleRect.topLeftY) / currentMonitor.visibleRect.height

            let workspaceRect = workspace.workspaceMonitor.visibleRect
            var newX = workspaceRect.topLeftX + xProportion * workspaceRect.width
            var newY = workspaceRect.topLeftY + yProportion * workspaceRect.height

            let windowWidth = windowRect.width
            let windowHeight = windowRect.height
            newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
            newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))

            setAxFrame(CGPoint(x: newX, y: newY), nil)
        }
        if isFullscreen {
            layoutFullscreen(context)
            isFullscreen = false
        }
    }

    @MainActor
    fileprivate func layoutFullscreen(_ context: LayoutContext) {
        let monitorRect = noOuterGapsInFullscreen
            ? context.workspace.workspaceMonitor.visibleRect
            : context.workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        setAxFrame(monitorRect.topLeftCorner, CGSize(width: monitorRect.width, height: monitorRect.height))
    }
}

extension TilingContainer {
    @MainActor
    fileprivate func layoutTiles(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        var point = point
        var virtualPoint = virtual.topLeftCorner

        guard let delta = ((orientation == .h ? width : height) - CGFloat(children.sumOfDouble { $0.getWeight(orientation) }))
            .div(children.count) else { return }

        let lastIndex = children.indices.last
        for (i, child) in children.enumerated() {
            child.setWeight(orientation, child.getWeight(orientation) + delta)
            let rawGap = context.resolvedGaps.inner.get(orientation).toDouble()
            // Gaps. Consider 4 cases:
            // 1. Multiple children. Layout first child
            // 2. Multiple children. Layout last child
            // 3. Multiple children. Layout child in the middle
            // 4. Single child   let rawGap = gaps.inner.get(orientation).toDouble()
            let gap = rawGap - (i == 0 ? rawGap / 2 : 0) - (i == lastIndex ? rawGap / 2 : 0)
            try await child.layoutRecursive(
                i == 0 ? point : point.addingOffset(orientation, rawGap / 2),
                width: orientation == .h ? child.hWeight - gap : width,
                height: orientation == .v ? child.vWeight - gap : height,
                virtual: Rect(
                    topLeftX: virtualPoint.x,
                    topLeftY: virtualPoint.y,
                    width: orientation == .h ? child.hWeight : width,
                    height: orientation == .v ? child.vWeight : height,
                ),
                context,
            )
            virtualPoint = orientation == .h ? virtualPoint.addingXOffset(child.hWeight) : virtualPoint.addingYOffset(child.vWeight)
            point = orientation == .h ? point.addingXOffset(child.hWeight) : point.addingYOffset(child.vWeight)
        }
    }

    @MainActor
    fileprivate func layoutAccordion(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        if usesWindowTabBehavior {
            let tabBarHeight = showsWindowTabs ? windowTabBarHeight : 0
            let contentPoint = point + CGPoint(x: 0, y: tabBarHeight)
            let contentHeight = max(height - tabBarHeight, 0)
            let contentVirtual = Rect(
                topLeftX: virtual.topLeftX,
                topLeftY: virtual.topLeftY + tabBarHeight,
                width: virtual.width,
                height: max(virtual.height - tabBarHeight, 0),
            )
            guard let activeChild = mostRecentChild else { return }

            for child in children where child != activeChild {
                try await child.hideTabbedWindows(context.workspace)
            }
            try await activeChild.layoutRecursive(
                contentPoint,
                width: width,
                height: contentHeight,
                virtual: contentVirtual,
                context,
            )
            return
        }

        guard let mruIndex: Int = mostRecentChild?.ownIndex else { return }
        for (index, child) in children.enumerated() {
            let padding = CGFloat(config.accordionPadding)
            let (lPadding, rPadding): (CGFloat, CGFloat) = switch index {
                case 0 where children.count == 1: (0, 0)
                case 0:                           (0, padding)
                case children.indices.last:       (padding, 0)
                case mruIndex - 1:                (0, 2 * padding)
                case mruIndex + 1:                (2 * padding, 0)
                default:                          (padding, padding)
            }
            switch orientation {
                case .h:
                    try await child.layoutRecursive(
                        point + CGPoint(x: lPadding, y: 0),
                        width: width - rPadding - lPadding,
                        height: height,
                        virtual: virtual,
                        context,
                    )
                case .v:
                    try await child.layoutRecursive(
                        point + CGPoint(x: 0, y: lPadding),
                        width: width,
                        height: height - lPadding - rPadding,
                        virtual: virtual,
                        context,
                    )
            }
        }
    }
}

extension TreeNode {
    @MainActor
    fileprivate func hideTabbedWindows(_ workspace: Workspace) async throws {
        switch nodeCases {
            case .window(let window):
                window.lastAppliedLayoutPhysicalRect = nil
                window.lastAppliedLayoutVirtualRect = nil
                if let macWindow = window as? MacWindow {
                    try await macWindow.hideInCorner(.bottomRightCorner)
                }
            case .tilingContainer(let container):
                for child in container.children {
                    try await child.hideTabbedWindows(workspace)
                }
            case .workspace, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return
        }
    }

    @MainActor
    fileprivate func hideAllWindowsExcept(_ targetWindow: Window) async throws {
        switch nodeCases {
            case .window(let window):
                guard window != targetWindow else { return }
                window.lastAppliedLayoutPhysicalRect = nil
                window.lastAppliedLayoutVirtualRect = nil
                if let macWindow = window as? MacWindow {
                    try await macWindow.hideInCorner(.bottomRightCorner)
                }
            case .tilingContainer(let container):
                for child in container.children {
                    try await child.hideAllWindowsExcept(targetWindow)
                }
            case .workspace(let workspace):
                for child in workspace.children {
                    try await child.hideAllWindowsExcept(targetWindow)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return
        }
    }
}
