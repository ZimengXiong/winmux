import AppKit
import Common

extension Rect {
    static func union(_ rects: some Sequence<Rect>) -> Rect? {
        var iterator = rects.makeIterator()
        guard let first = iterator.next() else { return nil }
        var minX = first.minX
        var minY = first.minY
        var maxX = first.maxX
        var maxY = first.maxY
        while let rect = iterator.next() {
            minX = min(minX, rect.minX)
            minY = min(minY, rect.minY)
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }
        return Rect(topLeftX: minX, topLeftY: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension TreeNode {
    @MainActor
    var windowDragVisibleRect: Rect? {
        switch self {
            case let window as Window:
                return currentWindowDragActualRect(window) ?? window.lastAppliedLayoutPhysicalRect
            case let container as TilingContainer:
                if container.layout == .tabGroup {
                    let activeWindowRect = container.tabActiveWindow?.windowDragVisibleRect
                    let tabBarRect = container.windowTabBarRect
                    return Rect.union([activeWindowRect, tabBarRect].compactMap { $0 }) ?? container.lastAppliedLayoutPhysicalRect
                }
                let childRects = container.children.compactMap { $0.windowDragVisibleRect }
                return Rect.union(childRects) ?? container.lastAppliedLayoutPhysicalRect
            default:
                return lastAppliedLayoutPhysicalRect
        }
    }
}

extension Window {
    @MainActor
    var tabStackTargetRects: (containerRect: Rect, previewRect: Rect, interactionRect: Rect)? {
        if let parent = parent as? TilingContainer,
           parent.layout == .tabGroup,
           let previewRect = parent.windowTabDropZoneRect,
           let interactionRect = parent.windowTabDropInteractionRect
        {
            return (
                containerRect: parent.windowDragVisibleRect ?? previewRect,
                previewRect: previewRect,
                interactionRect: interactionRect,
            )
        }
        guard let previewRect = tabDropZoneRect,
              let interactionRect = tabDropInteractionRect
        else { return nil }
        return (
            containerRect: windowDragVisibleRect ?? previewRect,
            previewRect: previewRect,
            interactionRect: interactionRect,
        )
    }

    @MainActor
    var tabDropZoneRect: Rect? {
        guard let rect = windowDragVisibleRect else { return nil }
        return rect.tabInsertPreviewRect(barHeight: resolvedWindowTabBarHeight())
    }

    @MainActor
    var tabDropInteractionRect: Rect? {
        guard let rect = windowDragVisibleRect else { return nil }
        return rect.tabInsertInteractionRect(barHeight: resolvedWindowTabBarHeight())
    }

    @MainActor
    var tabDetachPreviewRect: Rect? {
        if let parent = parent as? TilingContainer,
           parent.layout == .tabGroup,
           let rect = parent.lastAppliedLayoutPhysicalRect
        {
            return rect
        }
        return lastAppliedLayoutPhysicalRect
    }

    @MainActor
    func tabDetachKeepRect(origin: TabDetachOrigin) -> Rect? {
        guard let parent = parent as? TilingContainer, parent.layout == .tabGroup else { return nil }
        return switch origin {
            case .window:
                lastAppliedLayoutPhysicalRect?.expanded(left: 8, right: 8, top: 8, bottom: 12)
                    ?? parent.lastAppliedLayoutPhysicalRect?.insetBy(left: 24, right: 24, top: 14, bottom: 18)
            case .tabStrip:
                (parent.windowTabDropZoneRect ?? parent.windowTabBarRect)?.expanded(left: 4, right: 4, top: 4, bottom: 6)
        }
    }
}

extension CGPoint {
    @MainActor
    func findWindowDragTarget(in tree: TilingContainer, excluding excludedNode: TreeNode? = nil) -> Window? {
        findWindowDragTarget(in: tree as TreeNode, excluding: excludedNode)
    }

    @MainActor
    func shouldExcludeDragTargetNode(_ node: TreeNode, excludedNode: TreeNode?) -> Bool {
        guard let excludedNode else { return false }
        guard let excludedTabGroup = excludedNode as? TilingContainer,
              excludedTabGroup.layout == .tabGroup
        else {
            if node === excludedNode { return true }
            return node.parentsWithSelf.contains(excludedNode)
        }
        if node === excludedTabGroup { return false }
        if let window = node as? Window, window.parent === excludedTabGroup {
            return false
        }
        return node.parentsWithSelf.contains(excludedNode)
    }

    @MainActor
    func findWindowDragTarget(in node: TreeNode, excluding excludedNode: TreeNode?) -> Window? {
        if shouldExcludeDragTargetNode(node, excludedNode: excludedNode) {
            return nil
        }
        guard node.windowDragVisibleRect?.contains(self) == true else { return nil }
        switch node.tilingTreeNodeCasesOrDie() {
            case .window(let window):
                return window
            case .tilingContainer(let container):
                switch container.layout {
                    case .tiles:
                        let candidates = container.childrenByMostRecentUse.filter { $0.windowDragVisibleRect?.contains(self) == true }
                        if candidates.count > 1 {
                            let candidateSummary = candidates.map { candidate in
                                if let window = candidate as? Window {
                                    return "w:\(window.windowId) visible=\(debugDescribe(candidate.windowDragVisibleRect))"
                                } else {
                                    return "node:\(ObjectIdentifier(candidate)) visible=\(debugDescribe(candidate.windowDragVisibleRect))"
                                }
                            }.joined(separator: " | ")
                            let signature = "surface-overlap:container=\(ObjectIdentifier(container).hashValue):excluded=\(ObjectIdentifier(excludedNode ?? NilTreeNode.instance).hashValue):candidates=\(candidates.map { ObjectIdentifier($0).hashValue })"
                            logWindowDragHitTestIfNeeded(
                                signature: signature,
                                "windowDragTarget.overlap mouse=\(debugDescribe(self)) container=\(ObjectIdentifier(container)) excluded=\(String(describing: excludedNode.map(ObjectIdentifier.init))) candidates=[\(candidateSummary)]"
                            )
                        }
                        for child in candidates {
                            if let window = findWindowDragTarget(in: child, excluding: excludedNode) {
                                return window
                            }
                        }
                        return nil
                    case .tabGroup:
                        if container.usesWindowTabBehavior {
                            guard let targetWindow = container.tabActiveWindow ??
                                container.mostRecentWindowRecursive ??
                                container.anyLeafWindowRecursive
                            else { return nil }
                            return shouldExcludeDragTargetNode(targetWindow, excludedNode: excludedNode) ? nil : targetWindow
                        }
                        let candidates = container.childrenByMostRecentUse.filter { $0.windowDragVisibleRect?.contains(self) == true }
                        for child in candidates {
                            if let window = findWindowDragTarget(in: child, excluding: excludedNode) {
                                return window
                            }
                        }
                        return nil
                }
        }
    }

    @MainActor
    func findWindowTabDropDestination(in tree: TilingContainer, excluding sourceWindow: Window) -> WindowDragIntentDestination? {
        findWindowTabDropDestination(in: tree as TreeNode, excluding: sourceWindow)
    }

    @MainActor
    func findWindowTabDropDestination(in node: TreeNode, excluding sourceWindow: Window) -> WindowDragIntentDestination? {
        guard node.windowDragVisibleRect?.contains(self) == true else { return nil }
        switch node.tilingTreeNodeCasesOrDie() {
            case .window(let window):
                guard window != sourceWindow else { return nil }
                return tabStackDestination(targetWindow: window, mouseLocation: self)
            case .tilingContainer(let container):
                if let targetWindow = container.tabActiveWindow, targetWindow != sourceWindow,
                   let destination = tabStackDestination(targetWindow: targetWindow, mouseLocation: self)
                {
                    return destination
                }

                switch container.layout {
                    case .tiles:
                        for child in container.childrenByMostRecentUse where child.windowDragVisibleRect?.contains(self) == true {
                            if let destination = findWindowTabDropDestination(in: child, excluding: sourceWindow) {
                                return destination
                            }
                        }
                        return nil
                    case .tabGroup:
                        if container.usesWindowTabBehavior {
                            return nil
                        }
                        for child in container.childrenByMostRecentUse where child.windowDragVisibleRect?.contains(self) == true {
                            if let destination = findWindowTabDropDestination(in: child, excluding: sourceWindow) {
                                return destination
                            }
                        }
                        return nil
                }
        }
    }
}

@MainActor
func currentStickyWindowDragIntentDestination(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    guard let sticky = pendingWindowDragIntent,
          sticky.sourceWindowId == sourceWindow.windowId,
          sticky.sourceSubject == subject,
          shouldUseStickyWindowDragIntent(previewStyle: sticky.previewStyle),
          let targetWindow = stickyTargetWindow(for: sticky),
          let trackingRect = stickyTargetTrackingRect(targetWindow: targetWindow, previewStyle: sticky.previewStyle),
          trackingRect.contains(mouseLocation)
    else { return nil }

    let intentReferenceRect: Rect? = switch sticky.previewStyle {
        case .tabInsert:
            targetWindow.windowDragVisibleRect
        case .stackSplit, .swap:
            targetWindow.moveNode.windowDragVisibleRect
        case .detach, .workspaceMove, .sidebarWorkspaceMove:
            nil
    }
    guard let intentReferenceRect else { return nil }
    logWindowDragHitTestIfNeeded(
        signature: "sticky:target=\(targetWindow.windowId):style=\(sticky.previewStyle):preview=\(debugDescribe(sticky.previewRect))",
        "windowDragTarget.sticky source=\(debugDescribe(sourceWindow)) subject=\(debugDescribe(subject)) mouse=\(debugDescribe(mouseLocation)) target=\(debugDescribe(targetWindow)) trackingRect=\(debugDescribe(trackingRect)) referenceRect=\(debugDescribe(intentReferenceRect)) preview=\(debugDescribe(sticky.previewRect)) style=\(sticky.previewStyle)"
    )
    return windowSurfaceDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        mouseLocation: intentReferenceRect.clampedPoint(mouseLocation),
        subject: subject,
        detachOrigin: detachOrigin,
    )
}
