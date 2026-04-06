import AppKit
import Common

private let windowDropPreviewInset: CGFloat = 1
private let windowTabInsertPreviewExtraHeight: CGFloat = 18
private let windowTabInsertPreviewMinHeight: CGFloat = 56
private let windowTabInsertInteractionHorizontalInset: CGFloat = 24
private let windowTabInsertInteractionTopInset: CGFloat = 12
private let windowTabInsertInteractionBottomInset: CGFloat = 26
private let windowTabInsertStickyTrackingHorizontalInset: CGFloat = 24
private let windowTabInsertStickyTrackingTopInset: CGFloat = 20
private let windowTabInsertStickyTrackingBottomInset: CGFloat = 36

@MainActor
private var pendingWindowDragIntent: PendingWindowDragIntent? = nil
@MainActor
private var windowDragActualRectRefreshTask: Task<Void, Never>? = nil
@MainActor
private var windowDragActualRectCache: [UInt32: Rect] = [:]
@MainActor
private var lastWindowDragHitTestLogSignature: String? = nil
@MainActor
private var lastWindowDragIntentLogSignature: String? = nil

private struct PendingWindowDragIntent {
    let sourceWindowId: UInt32
    let sourceSubject: WindowDragSubject
    let kind: WindowDragIntentKind
    let previewRect: Rect
    let interactionRect: Rect
    let title: String
    let subtitle: String
    let previewStyle: WindowTabDropPreviewStyle
    let previewGeometry: WindowTabDropPreviewGeometry
    let isGroup: Bool
}

@MainActor
func debugPendingWindowDragIntentSummary() -> (kind: WindowDragIntentKind, previewRect: Rect, interactionRect: Rect)? {
    guard let pendingWindowDragIntent else { return nil }
    return (
        kind: pendingWindowDragIntent.kind,
        previewRect: pendingWindowDragIntent.previewRect,
        interactionRect: pendingWindowDragIntent.interactionRect,
    )
}

enum WindowStackSplitPosition: Equatable {
    case left
    case right
    case above
    case below

    var orientation: Orientation {
        switch self {
            case .left, .right: .h
            case .above, .below: .v
        }
    }

    var isPositive: Bool {
        switch self {
            case .right, .below: true
            case .left, .above: false
        }
    }

    var title: String {
        switch self {
            case .left: "Stack Left"
            case .right: "Stack Right"
            case .above: "Stack Above"
            case .below: "Stack Below"
        }
    }

    var subtitle: String {
        switch self {
            case .left: "Drop to split this tile and place the dragged item on the left"
            case .right: "Drop to split this tile and place the dragged item on the right"
            case .above: "Drop to split this tile and place the dragged item above"
            case .below: "Drop to split this tile and place the dragged item below"
        }
    }

    var previewGeometry: WindowTabDropPreviewGeometry {
        switch self {
            case .left: .splitLeft
            case .right: .splitRight
            case .above: .splitAbove
            case .below: .splitBelow
        }
    }
}

enum WindowDragIntentKind: Equatable {
    case tabStack(targetWindowId: UInt32)
    case detachTab(windowId: UInt32)
    case stackSplit(targetWindowId: UInt32, position: WindowStackSplitPosition)
    case swap(targetWindowId: UInt32)
    case moveToWorkspace(workspaceName: String)
    case createWorkspace
    case sidebarHover
}

enum WindowBodyDragIntent: Equatable {
    case stackSplit(WindowStackSplitPosition)
    case swap
}

@MainActor
func isWindowDragIntentKindEnabled(_ kind: WindowDragIntentKind) -> Bool {
    switch kind {
        case .tabStack:
            return config.windowTabs.enabled
        case .detachTab, .stackSplit, .swap, .moveToWorkspace, .createWorkspace, .sidebarHover:
            return true
    }
}

func shouldUseStickyWindowDragIntent(previewStyle: WindowTabDropPreviewStyle) -> Bool {
    switch previewStyle {
        case .tabInsert, .stackSplit, .swap:
            return true
        case .detach, .workspaceMove, .sidebarWorkspaceMove:
            return false
    }
}

enum WindowDragSubject: Equatable {
    case window
    case group
}

enum TabDetachOrigin: Equatable {
    case window
    case tabStrip
}

private struct WindowDragIntentDestination {
    let kind: WindowDragIntentKind
    let previewContainerRect: Rect
    let previewRect: Rect
    let interactionRect: Rect
    let title: String
    let subtitle: String
    let previewStyle: WindowTabDropPreviewStyle
    let previewGeometry: WindowTabDropPreviewGeometry
    let isGroup: Bool

    func preview(sourceWindowId: UInt32) -> WindowTabDropPreviewViewModel {
        WindowTabDropPreviewViewModel(
            containerFrame: previewContainerRect.toAppKitScreenRect,
            frame: previewRect.toAppKitScreenRect,
            title: title,
            subtitle: subtitle,
            style: previewStyle,
            geometry: previewGeometry,
            isGroup: isGroup,
            referenceWindowId: previewReferenceWindowId(sourceWindowId: sourceWindowId),
        )
    }

    private func previewReferenceWindowId(sourceWindowId: UInt32) -> UInt32? {
        switch kind {
            case .tabStack(let targetWindowId), .stackSplit(let targetWindowId, _), .swap(let targetWindowId):
                return targetWindowId
            case .detachTab(let windowId):
                return windowId
            case .moveToWorkspace, .createWorkspace, .sidebarHover:
                return sourceWindowId
        }
    }
}

struct WindowStackSplitPreview {
    let rect: Rect
    let geometry: WindowTabDropPreviewGeometry
}

private func debugDescribe(_ rect: Rect?) -> String {
    guard let rect else { return "nil" }
    return "(\(rect.topLeftX), \(rect.topLeftY), \(rect.width), \(rect.height))"
}

private func debugDescribe(_ point: CGPoint) -> String {
    "(\(point.x), \(point.y))"
}

func resolveWindowDragActualRect(cached: Rect?, candidate: Rect, layout: Rect?) -> Rect {
    guard let cached, let layout else { return candidate }
    guard candidate.isApproximatelyEqual(to: layout, tolerance: 1) else { return candidate }
    guard cached.area > candidate.area + 1 else { return candidate }
    guard cached.intersection(candidate).area >= candidate.area * 0.85 else { return candidate }
    return cached
}

@MainActor
private func currentWindowDragActualRect(_ window: Window) -> Rect? {
    guard let current = window.lastKnownActualRect else { return windowDragActualRectCache[window.windowId] }
    return resolveWindowDragActualRect(
        cached: windowDragActualRectCache[window.windowId],
        candidate: current,
        layout: window.lastAppliedLayoutPhysicalRect,
    )
}

private func debugDescribe(_ subject: WindowDragSubject) -> String {
    switch subject {
        case .window: "window"
        case .group: "group"
    }
}

private func debugDescribe(_ kind: WindowDragIntentKind) -> String {
    switch kind {
        case .tabStack(let targetWindowId):
            "tabStack(target:\(targetWindowId))"
        case .detachTab(let windowId):
            "detachTab(window:\(windowId))"
        case .stackSplit(let targetWindowId, let position):
            "stackSplit(target:\(targetWindowId), position:\(position))"
        case .swap(let targetWindowId):
            "swap(target:\(targetWindowId))"
        case .moveToWorkspace(let workspaceName):
            "moveToWorkspace(\(workspaceName))"
        case .createWorkspace:
            "createWorkspace"
        case .sidebarHover:
            "sidebarHover"
    }
}

private func debugDescribe(_ intent: WindowBodyDragIntent?) -> String {
    guard let intent else { return "nil" }
    switch intent {
        case .swap:
            return "swap"
        case .stackSplit(let position):
            return "stackSplit(\(position))"
    }
}

@MainActor
private func debugDescribe(_ window: Window?) -> String {
    guard let window else { return "nil" }
    return "w:\(window.windowId) actual=\(debugDescribe(window.lastKnownActualRect)) layout=\(debugDescribe(window.lastAppliedLayoutPhysicalRect)) visible=\(debugDescribe(window.windowDragVisibleRect)) moveVisible=\(debugDescribe(window.moveNode.windowDragVisibleRect))"
}

@MainActor
private func debugDescribe(_ node: TreeNode) -> String {
    switch node.tilingTreeNodeCasesOrDie() {
        case .window(let window):
            return "window[\(window.windowId)] visible=\(debugDescribe(node.windowDragVisibleRect))"
        case .tilingContainer(let container):
            return "container[\(ObjectIdentifier(container).hashValue)] layout=\(container.layout) visible=\(debugDescribe(node.windowDragVisibleRect))"
    }
}

@MainActor
private func logWindowDragHitTestIfNeeded(signature: String, _ message: @autoclosure () -> String) {
    guard lastWindowDragHitTestLogSignature != signature else { return }
    lastWindowDragHitTestLogSignature = signature
    debugFocusLog(message())
}

@MainActor
private func logWindowDragIntentIfNeeded(signature: String, _ message: @autoclosure () -> String) {
    guard lastWindowDragIntentLogSignature != signature else { return }
    lastWindowDragIntentLogSignature = signature
    debugFocusLog(message())
}

@MainActor
func refreshVisibleWindowActualRectsForCurrentDrag(sourceWindowId: UInt32) {
    windowDragActualRectRefreshTask?.cancel()
    windowDragActualRectRefreshTask = Task { @MainActor in
        let visibleWindows = Workspace.all
            .filter(\.isVisible)
            .flatMap(\.allLeafWindowsRecursive)
        windowDragActualRectCache = visibleWindows.reduce(into: [:]) { result, window in
            if let rect = window.lastKnownActualRect {
                result[window.windowId] = rect
            }
        }
        for window in visibleWindows {
            let previousRect = window.lastKnownActualRect
            let refreshedRect = try? await window.getAxRect()
            if let refreshedRect {
                windowDragActualRectCache[window.windowId] = resolveWindowDragActualRect(
                    cached: windowDragActualRectCache[window.windowId],
                    candidate: refreshedRect,
                    layout: window.lastAppliedLayoutPhysicalRect,
                )
            }
            if let refreshedRect, !(previousRect.map { $0.isEqual(to: refreshedRect) } ?? false) {
                debugFocusLog(
                    "windowDragActualRect.refresh source=\(sourceWindowId) target=\(window.windowId) old=\(debugDescribe(previousRect)) new=\(debugDescribe(refreshedRect)) layout=\(debugDescribe(window.lastAppliedLayoutPhysicalRect))"
                )
            }
        }
        guard currentlyManipulatedWithMouseWindowId == sourceWindowId,
              let sourceWindow = Window.get(byId: sourceWindowId)
        else { return }
        _ = updatePendingWindowDragIntent(
            sourceWindow: sourceWindow,
            mouseLocation: mouseLocation,
            subject: getCurrentMouseDragSubject(),
            detachOrigin: getCurrentMouseTabDetachOrigin(),
        )
    }
}

@MainActor
func cancelWindowDragActualRectRefresh() {
    windowDragActualRectRefreshTask?.cancel()
    windowDragActualRectRefreshTask = nil
    windowDragActualRectCache = [:]
    lastWindowDragHitTestLogSignature = nil
    lastWindowDragIntentLogSignature = nil
}

@MainActor
private func workspaceSidebarCursorPreviewRect(at mouseLocation: CGPoint) -> Rect {
    workspaceSidebarCursorPreviewRect(at: mouseLocation, sidebarRect: WorkspaceSidebarPanel.shared.visibleScreenRectNormalized())
}

private func workspaceSidebarCursorPreviewRect(at mouseLocation: CGPoint, sidebarRect: Rect?) -> Rect {
    let width: CGFloat = 184
    let height: CGFloat = 42
    if let sidebarRect {
        let horizontalInset: CGFloat = 10
        let verticalInset: CGFloat = 8
        let availableWidth = min(width, max(sidebarRect.width - horizontalInset * 2, 0))
        let clampedX = max(
            sidebarRect.minX + horizontalInset,
            min(mouseLocation.x - (availableWidth / 2), sidebarRect.maxX - availableWidth - horizontalInset),
        )
        let clampedY = max(
            sidebarRect.minY + verticalInset,
            min(mouseLocation.y - (height / 2), sidebarRect.maxY - height - verticalInset),
        )
        return Rect(
            topLeftX: clampedX,
            topLeftY: clampedY,
            width: availableWidth,
            height: height,
        )
    }
    return Rect(
        topLeftX: mouseLocation.x + 16,
        topLeftY: mouseLocation.y - height - 12,
        width: width,
        height: height,
    )
}

@MainActor
private func dragSubjectNode(for sourceWindow: Window, subject: WindowDragSubject) -> TreeNode {
    switch subject {
        case .window: sourceWindow
        case .group: sourceWindow.moveNode
    }
}

@MainActor
private func dragIntentTargetNode(
    sourceWindow: Window,
    targetWindow: Window,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> TreeNode {
    guard let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .accordion,
          targetWindow.parent === sourceParent
    else { return targetWindow.moveNode }

    if subject == .window, detachOrigin == .tabStrip {
        logWindowDragHitTestIfNeeded(
            signature: "self-accordion-target:source=\(sourceWindow.windowId):target=\(targetWindow.windowId)",
            "windowDragTarget.selfAccordion source=\(debugDescribe(sourceWindow)) target=\(debugDescribe(targetWindow)) chosen=\(debugDescribe(sourceParent)) reason=tab-strip-window-drag-over-own-accordion"
        )
        return sourceParent
    }
    if subject == .group, detachOrigin != .tabStrip {
        return targetWindow
    }
    return targetWindow.moveNode
}

@MainActor
private func allowsAccordionSelfTargeting(sourceNode: TreeNode, targetNode: TreeNode) -> Bool {
    if let sourceAccordion = sourceNode as? TilingContainer,
       sourceAccordion.layout == .accordion,
       let targetWindow = targetNode as? Window,
       targetWindow.parent === sourceAccordion
    {
        return true
    }
    guard let sourceAccordion = sourceNode as? TilingContainer,
          sourceAccordion.layout == .accordion
    else {
        return (sourceNode as? Window)?.parent === targetNode
    }
    return targetNode === sourceAccordion
}

@MainActor
private func isBlockedByDragTargetContainment(sourceNode: TreeNode, targetNode: TreeNode) -> Bool {
    if sourceNode == targetNode {
        return true
    }
    if sourceNode.parentsWithSelf.contains(targetNode) && !allowsAccordionSelfTargeting(sourceNode: sourceNode, targetNode: targetNode) {
        return true
    }
    if targetNode.parentsWithSelf.contains(sourceNode) && !allowsAccordionSelfTargeting(sourceNode: sourceNode, targetNode: targetNode) {
        return true
    }
    return false
}

@MainActor
private func sidebarDragSourceTitle(for sourceWindow: Window, subject: WindowDragSubject) -> String {
    let moveNode = dragSubjectNode(for: sourceWindow, subject: subject)
    if let group = moveNode as? TilingContainer {
        let windowCount = max(moveNode.allLeafWindowsRecursive.count, 1)
        let representativeWindow =
            group.tabActiveWindow ??
            group.mostRecentWindowRecursive ??
            group.anyLeafWindowRecursive ??
            sourceWindow
        return "\(sidebarDisplayLabel(for: representativeWindow)) • \(windowCount) windows"
    }
    return sidebarDisplayLabel(for: sourceWindow)
}

@MainActor
private func updateSidebarDragFeedback(sourceWindow: Window, subject: WindowDragSubject, destination: WindowDragIntentDestination?) {
    guard let destination, destination.previewStyle == .sidebarWorkspaceMove else {
        let hadPinnedWindow = hasPinnedDraggedWindow()
        setPinnedDraggedWindowId(nil)
        setWorkspaceSidebarDropPreviewIfChanged(nil)
        if hadPinnedWindow {
            scheduleRefreshSession(.globalObserver("sidebarGhostExit"), optimisticallyPreLayoutWorkspaces: true)
        }
        return
    }

    let moveNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let isTabGroup = moveNode is TilingContainer
    let windowCount = max(moveNode.allLeafWindowsRecursive.count, 1)
    let sourceLabel = sidebarDragSourceTitle(for: sourceWindow, subject: subject)
    let targetWorkspaceName: String? = switch destination.kind {
        case .moveToWorkspace(let workspaceName): workspaceName
        case .createWorkspace, .sidebarHover, .tabStack, .detachTab, .stackSplit, .swap: nil
    }
    if case .moveToWorkspace = destination.kind {
        setWorkspaceSidebarDropPreviewIfChanged(WorkspaceSidebarDropPreviewViewModel(
            sourceWindowId: sourceWindow.windowId,
            label: sourceLabel,
            targetWorkspaceName: targetWorkspaceName,
            targetsNewWorkspace: false,
            isTabGroup: isTabGroup,
            windowCount: windowCount,
        ))
    } else if destination.kind == .createWorkspace {
        setWorkspaceSidebarDropPreviewIfChanged(WorkspaceSidebarDropPreviewViewModel(
            sourceWindowId: sourceWindow.windowId,
            label: sourceLabel,
            targetWorkspaceName: nil,
            targetsNewWorkspace: true,
            isTabGroup: isTabGroup,
            windowCount: windowCount,
        ))
    } else {
        setWorkspaceSidebarDropPreviewIfChanged(nil)
    }

    let pinnedWindowId = currentlyManipulatedWithMouseWindowId == sourceWindow.windowId ? sourceWindow.windowId : nil
    let previousPinnedWindowId = isPinnedDraggedWindow(sourceWindow.windowId) ? sourceWindow.windowId : nil
    if let pinnedWindowId, let anchorRect = draggedWindowAnchorRect(for: pinnedWindowId) {
        let pinnedWindowRect = pinnedDraggedWindowRect(
            for: sourceWindow,
            subject: subject,
            fallbackAnchorRect: anchorRect,
        )
        sourceWindow.setAxFrame(pinnedWindowRect.topLeftCorner, pinnedWindowRect.size)
    }
    if pinnedWindowId != previousPinnedWindowId {
        setPinnedDraggedWindowId(pinnedWindowId)
        scheduleRefreshSession(.globalObserver("sidebarGhostEnter"), optimisticallyPreLayoutWorkspaces: true)
    } else {
        setPinnedDraggedWindowId(pinnedWindowId)
    }
}

@MainActor
func pinnedDraggedWindowRect(for sourceWindow: Window, subject: WindowDragSubject, fallbackAnchorRect: Rect) -> Rect {
    switch subject {
        case .window:
            return fallbackAnchorRect
        case .group:
            return resolvedDraggedWindowAnchorRect(for: sourceWindow, subject: .window) ?? fallbackAnchorRect
    }
}

@MainActor
private func setWorkspaceSidebarDropPreviewIfChanged(_ preview: WorkspaceSidebarDropPreviewViewModel?) {
    if TrayMenuModel.shared.workspaceSidebarDropPreview != preview {
        TrayMenuModel.shared.workspaceSidebarDropPreview = preview
    }
}

@MainActor
private func tabStackDestination(targetWindow: Window, mouseLocation: CGPoint? = nil) -> WindowDragIntentDestination? {
    guard isWindowDragIntentKindEnabled(.tabStack(targetWindowId: targetWindow.windowId)),
          let dropRect = targetWindow.tabDropZoneRect,
          let interactionRect = targetWindow.tabDropInteractionRect,
          mouseLocation.map(interactionRect.contains) ?? true
    else { return nil }
    return WindowDragIntentDestination(
        kind: .tabStack(targetWindowId: targetWindow.windowId),
        previewContainerRect: targetWindow.windowDragVisibleRect ?? dropRect,
        previewRect: dropRect,
        interactionRect: interactionRect,
        title: "Insert Into Tabs",
        subtitle: "Drop near the top edge to add this window",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
    )
}

@MainActor
private func selfAccordionTabReentryDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    guard subject == .window,
          detachOrigin == .tabStrip,
          config.windowTabs.enabled,
          let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .accordion,
          targetWindow.parent === sourceParent,
          let previewRect = sourceParent.windowTabDropZoneRect,
          let interactionRect = sourceParent.windowTabDropInteractionRect,
          interactionRect.contains(mouseLocation)
    else { return nil }

    return WindowDragIntentDestination(
        kind: .tabStack(targetWindowId: targetWindow.windowId),
        previewContainerRect: sourceParent.windowDragVisibleRect ?? previewRect,
        previewRect: previewRect,
        interactionRect: interactionRect,
        title: "Return To Tabs",
        subtitle: "Drop to cancel the detach and put this tab back in the group",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
    )
}

@MainActor
private func swapDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint? = nil,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if shouldSuppressSameAccordionSwapDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: subject,
        detachOrigin: detachOrigin
    ) {
        return nil
    }
    if shouldSuppressSwapDestination(sourceWindow: sourceWindow, subject: subject) {
        return nil
    }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetNode = dragIntentTargetNode(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: subject,
        detachOrigin: detachOrigin,
    )
    guard !isBlockedByDragTargetContainment(sourceNode: sourceNode, targetNode: targetNode),
          let previewRect = targetNode.swapDropZoneRect
    else { return nil }
    let interactionRect = if subject == .group {
        previewRect.expanded(left: 4, right: 4, top: 4, bottom: 6)
    } else {
        previewRect.expanded(left: 10, right: 10, top: 10, bottom: 10)
    }
    guard mouseLocation.map(interactionRect.contains) ?? true else { return nil }
    let isTabGroup = targetNode is TilingContainer
    return WindowDragIntentDestination(
        kind: .swap(targetWindowId: targetWindow.windowId),
        previewContainerRect: targetNode.windowDragVisibleRect ?? previewRect,
        previewRect: previewRect,
        interactionRect: interactionRect,
        title: isTabGroup ? "Swap With Tab Group" : "Swap Positions",
        subtitle: isTabGroup ? "Drop in the body to move around the whole group" : "Drop in the body to swap these windows",
        previewStyle: .swap,
        previewGeometry: .rounded,
        isGroup: subject == .group,
    )
}

@MainActor
private func stackSplitDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint? = nil,
    subject: WindowDragSubject,
    position: WindowStackSplitPosition,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if shouldSuppressSwapDestination(sourceWindow: sourceWindow, subject: subject) {
        return nil
    }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetNode = dragIntentTargetNode(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: subject,
        detachOrigin: detachOrigin,
    )
    guard !isBlockedByDragTargetContainment(sourceNode: sourceNode, targetNode: targetNode),
          canOfferWindowStackSplit(sourceNode: sourceNode, targetNode: targetNode, position: position),
          let preview = resolvedWindowStackSplitPreview(targetNode: targetNode, position: position),
          let interactionRect = targetNode.stackSplitDropZoneRect(position: position)?
          .expanded(left: subject == .group ? 4 : 10, right: subject == .group ? 4 : 10, top: 0, bottom: 0)
    else { return nil }
    guard mouseLocation.map(interactionRect.contains) ?? true else { return nil }
    return WindowDragIntentDestination(
        kind: .stackSplit(targetWindowId: targetWindow.windowId, position: position),
        previewContainerRect: targetNode.windowDragVisibleRect ?? preview.rect,
        previewRect: preview.rect,
        interactionRect: interactionRect,
        title: position.title,
        subtitle: position.subtitle,
        previewStyle: .stackSplit,
        previewGeometry: preview.geometry,
        isGroup: subject == .group,
    )
}

@MainActor
private func currentWindowTabDropDestination(sourceWindow: Window, mouseLocation: CGPoint) -> WindowDragIntentDestination? {
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    return mouseLocation.findWindowTabDropDestination(in: targetWorkspace.rootTilingContainer, excluding: sourceWindow)
}

@MainActor
private func windowSurfaceDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    let targetNode = dragIntentTargetNode(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: subject,
        detachOrigin: detachOrigin,
    )
    if let reentryDestination = selfAccordionTabReentryDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    ) {
        return reentryDestination
    }
    if subject == .window,
       config.windowTabs.enabled,
       let tabDestination = tabStackDestination(targetWindow: targetWindow, mouseLocation: mouseLocation)
    {
        if case .tabStack(let targetWindowId) = tabDestination.kind,
           let targetWindow = Window.get(byId: targetWindowId),
           shouldSuppressSameAccordionTabDestination(
               sourceWindow: sourceWindow,
               targetWindow: targetWindow,
               detachOrigin: detachOrigin,
           )
        {
            // Body drags from an existing tab group should be able to detach instead of
            // being trapped by that same group's own tab insert target.
        } else {
            return tabDestination
        }
    }

    let bodyIntent = targetNode.bodyDragIntent(at: mouseLocation)
    if detachOrigin == .tabStrip,
       subject == .window,
       let sourceParent = sourceWindow.parent as? TilingContainer,
       sourceParent.layout == .accordion,
       targetWindow.parent === sourceParent
    {
        logWindowDragHitTestIfNeeded(
            signature: "self-accordion-intent:source=\(sourceWindow.windowId):target=\(targetWindow.windowId):intent=\(debugDescribe(bodyIntent))",
            "windowDragTarget.selfAccordionIntent mouse=\(debugDescribe(mouseLocation)) source=\(debugDescribe(sourceWindow)) target=\(debugDescribe(targetWindow)) targetNode=\(debugDescribe(targetNode)) visible=\(debugDescribe(targetNode.windowDragVisibleRect)) swap=\(debugDescribe(targetNode.swapDropZoneRect)) left=\(debugDescribe(targetNode.stackSplitDropZoneRect(position: .left))) right=\(debugDescribe(targetNode.stackSplitDropZoneRect(position: .right))) above=\(debugDescribe(targetNode.stackSplitDropZoneRect(position: .above))) below=\(debugDescribe(targetNode.stackSplitDropZoneRect(position: .below))) resolved=\(debugDescribe(bodyIntent))"
        )
    }

    switch bodyIntent {
        case .stackSplit(let position):
            return stackSplitDestination(
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                position: position,
                detachOrigin: detachOrigin,
            )
        case .swap:
            return swapDestination(
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                detachOrigin: detachOrigin,
            )
        case nil:
            return nil
    }
}

@MainActor
private func currentWindowSurfaceDestination(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if subject == .window,
       detachOrigin == .tabStrip,
       let sourceParent = sourceWindow.parent as? TilingContainer,
       sourceParent.layout == .accordion,
       sourceParent.windowDragVisibleRect?.contains(mouseLocation) == true
    {
        let targetWindow =
            sourceParent.tabActiveWindow ??
            sourceParent.mostRecentWindowRecursive ??
            sourceParent.anyLeafWindowRecursive ??
            sourceWindow
        logWindowDragHitTestIfNeeded(
            signature: "surface:self-accordion-direct:source=\(sourceWindow.windowId)",
            "windowDragTarget.selfAccordionDirect source=\(debugDescribe(sourceWindow)) mouse=\(debugDescribe(mouseLocation)) target=\(debugDescribe(targetWindow)) container=\(debugDescribe(sourceParent))"
        )
        return windowSurfaceDestination(
            sourceWindow: sourceWindow,
            targetWindow: targetWindow,
            mouseLocation: mouseLocation,
            subject: subject,
            detachOrigin: detachOrigin,
        )
    }

    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    guard let targetWindow = mouseLocation.findWindowDragTarget(in: targetWorkspace.rootTilingContainer, excluding: sourceNode) else {
        logWindowDragHitTestIfNeeded(
            signature: "surface:none:source=\(sourceWindow.windowId):subject=\(debugDescribe(subject))",
            "windowDragTarget.none source=\(debugDescribe(sourceWindow)) subject=\(debugDescribe(subject)) mouse=\(debugDescribe(mouseLocation)) workspace=\(targetWorkspace.name)"
        )
        return nil
    }
    logWindowDragHitTestIfNeeded(
        signature: "surface:target=\(targetWindow.windowId):source=\(sourceWindow.windowId):subject=\(debugDescribe(subject))",
        "windowDragTarget.surface source=\(debugDescribe(sourceWindow)) subject=\(debugDescribe(subject)) mouse=\(debugDescribe(mouseLocation)) target=\(debugDescribe(targetWindow))"
    )
    return windowSurfaceDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    )
}

@MainActor
private func stickyTargetWindow(for sticky: PendingWindowDragIntent) -> Window? {
    switch sticky.kind {
        case .tabStack(let targetWindowId), .stackSplit(let targetWindowId, _), .swap(let targetWindowId):
            Window.get(byId: targetWindowId)
        case .detachTab, .moveToWorkspace, .createWorkspace, .sidebarHover:
            nil
    }
}

@MainActor
private func stickyTargetTrackingRect(targetWindow: Window, previewStyle: WindowTabDropPreviewStyle) -> Rect? {
    switch previewStyle {
        case .tabInsert:
            targetWindow.windowDragVisibleRect?.expanded(
                left: windowTabInsertStickyTrackingHorizontalInset,
                right: windowTabInsertStickyTrackingHorizontalInset,
                top: windowTabInsertStickyTrackingTopInset,
                bottom: windowTabInsertStickyTrackingBottomInset
            )
        case .stackSplit, .swap:
            targetWindow.moveNode.windowDragVisibleRect?.expanded(by: 16)
        case .detach, .workspaceMove, .sidebarWorkspaceMove:
            nil
    }
}

func isActionableSidebarWorkspaceDropTarget(
    sourceWorkspaceName: String?,
    targetKind: WorkspaceSidebarDropTargetKind?,
) -> Bool {
    switch targetKind {
        case .workspace(let workspaceName):
            return sourceWorkspaceName != workspaceName
        case .newWorkspace:
            return true
        case nil:
            return false
    }
}

@MainActor
private func currentSidebarWorkspaceDropDestination(sourceWindow: Window, mouseLocation: CGPoint, subject: WindowDragSubject) -> WindowDragIntentDestination? {
    let sourceLabel = sidebarDragSourceTitle(for: sourceWindow, subject: subject)
    let isGroup = subject == .group
    let sourceWorkspaceName = dragSubjectNode(for: sourceWindow, subject: subject).nodeWorkspace?.name
    if let target = workspaceSidebarDropTarget(at: mouseLocation),
       isActionableSidebarWorkspaceDropTarget(sourceWorkspaceName: sourceWorkspaceName, targetKind: target.kind)
    {
        switch target.kind {
            case .workspace(let workspaceName):
                return WindowDragIntentDestination(
                    kind: .moveToWorkspace(workspaceName: workspaceName),
                    previewContainerRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                    previewRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                    interactionRect: target.rect.expanded(left: 14, right: 14, top: 12, bottom: 12),
                    title: sourceLabel,
                    subtitle: "Drop to send this item to \(workspaceName)",
                    previewStyle: .sidebarWorkspaceMove,
                    previewGeometry: .rounded,
                    isGroup: isGroup,
                )
            case .newWorkspace:
                return WindowDragIntentDestination(
                    kind: .createWorkspace,
                    previewContainerRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                    previewRect: workspaceSidebarCursorPreviewRect(at: mouseLocation),
                    interactionRect: target.rect.expanded(left: 14, right: 14, top: 12, bottom: 12),
                    title: sourceLabel,
                    subtitle: "Drop to create a workspace and move this item there",
                    previewStyle: .sidebarWorkspaceMove,
                    previewGeometry: .rounded,
                    isGroup: isGroup,
                )
        }
    }
    return nil
}

@MainActor
private func currentTabDetachDestination(sourceWindow: Window, mouseLocation: CGPoint, origin: TabDetachOrigin) -> WindowDragIntentDestination? {
    guard let parent = sourceWindow.parent as? TilingContainer,
          parent.layout == .accordion,
          parent.children.count > 1,
          let keepRect = sourceWindow.tabDetachKeepRect(origin: origin),
          !keepRect.contains(mouseLocation),
          let previewRect = sourceWindow.tabDetachPreviewRect
    else { return nil }

    return WindowDragIntentDestination(
        kind: .detachTab(windowId: sourceWindow.windowId),
        previewContainerRect: sourceWindow.windowDragVisibleRect ?? previewRect,
        previewRect: previewRect,
        interactionRect: previewRect.expanded(left: 18, right: 18, top: 10, bottom: 18),
        title: "Detach Tab",
        subtitle: "Release to pull this window out of the stack",
        previewStyle: .detach,
        previewGeometry: .rounded,
        isGroup: false,
    )
}

@MainActor
func shouldSuppressSameAccordionTabDestination(sourceWindow: Window, targetWindow: Window, detachOrigin _: TabDetachOrigin) -> Bool {
    guard let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .accordion,
          targetWindow.parent === sourceParent
    else { return false }
    return true
}

@MainActor
private func shouldSuppressSameAccordionSwapDestination(
    sourceWindow: Window,
    targetWindow: Window,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> Bool {
    guard subject == .window,
          detachOrigin == .tabStrip,
          let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .accordion,
          targetWindow.parent === sourceParent
    else { return false }
    return true
}

extension Rect {
    fileprivate static func union(_ rects: some Sequence<Rect>) -> Rect? {
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
    fileprivate var windowDragVisibleRect: Rect? {
        switch self {
            case let window as Window:
                return currentWindowDragActualRect(window) ?? window.lastAppliedLayoutPhysicalRect
            case let container as TilingContainer:
                if container.layout == .accordion {
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
    var tabDropZoneRect: Rect? {
        guard let rect = windowDragVisibleRect else { return nil }
        return rect.tabInsertPreviewRect(barHeight: CGFloat(config.windowTabs.height))
    }

    @MainActor
    var tabDropInteractionRect: Rect? {
        guard let rect = windowDragVisibleRect else { return nil }
        return rect.tabInsertInteractionRect(barHeight: CGFloat(config.windowTabs.height))
    }

    @MainActor
    var tabDetachPreviewRect: Rect? {
        if let parent = parent as? TilingContainer,
           parent.layout == .accordion,
           let rect = parent.lastAppliedLayoutPhysicalRect
        {
            return rect.insetBy(left: 2, right: 2, top: 2, bottom: 2)
        }
        return lastAppliedLayoutPhysicalRect?.insetBy(left: 2, right: 2, top: 2, bottom: 2)
    }

    @MainActor
    func tabDetachKeepRect(origin: TabDetachOrigin) -> Rect? {
        guard let parent = parent as? TilingContainer, parent.layout == .accordion else { return nil }
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
    private func shouldExcludeDragTargetNode(_ node: TreeNode, excludedNode: TreeNode?) -> Bool {
        guard let excludedNode else { return false }
        guard let excludedAccordion = excludedNode as? TilingContainer,
              excludedAccordion.layout == .accordion
        else {
            if node === excludedNode { return true }
            return node.parentsWithSelf.contains(excludedNode)
        }
        if node === excludedAccordion { return false }
        if let window = node as? Window, window.parent === excludedAccordion {
            return false
        }
        return node.parentsWithSelf.contains(excludedNode)
    }

    @MainActor
    private func findWindowDragTarget(in node: TreeNode, excluding excludedNode: TreeNode?) -> Window? {
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
                    case .accordion:
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
    fileprivate func findWindowTabDropDestination(in tree: TilingContainer, excluding sourceWindow: Window) -> WindowDragIntentDestination? {
        findWindowTabDropDestination(in: tree as TreeNode, excluding: sourceWindow)
    }

    @MainActor
    private func findWindowTabDropDestination(in node: TreeNode, excluding sourceWindow: Window) -> WindowDragIntentDestination? {
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
                    case .accordion:
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
private func currentStickyWindowDragIntentDestination(
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

@MainActor
func updatePendingWindowDragIntent(sourceWindow: Window, mouseLocation: CGPoint) -> Bool {
    updatePendingWindowDragIntent(sourceWindow: sourceWindow, mouseLocation: mouseLocation, subject: .window, detachOrigin: .window)
}

@MainActor
func updatePendingWindowDragIntent(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> Bool {
    WindowDragCursorProxyPanel.shared.hide()

    guard let destination = currentWindowDragIntentDestination(
        sourceWindow: sourceWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    ) else {
        updateSidebarDragFeedback(sourceWindow: sourceWindow, subject: subject, destination: nil)
        clearPendingWindowDragIntent()
        return false
    }
    updateSidebarDragFeedback(sourceWindow: sourceWindow, subject: subject, destination: destination)
    return setPendingWindowDragIntent(sourceWindowId: sourceWindow.windowId, sourceSubject: subject, destination: destination)
}

@MainActor
func updatePendingDetachedTabIntent(sourceWindow: Window, mouseLocation: CGPoint, origin: TabDetachOrigin) -> Bool {
    updatePendingWindowDragIntent(sourceWindow: sourceWindow, mouseLocation: mouseLocation, subject: .window, detachOrigin: origin)
}

@MainActor
func refreshPendingWindowDragIntentFromGlobalMouseDrag() {
    guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .move else {
        clearPendingWindowDragIntent()
        return
    }
    guard let windowId = currentlyManipulatedWithMouseWindowId,
          let sourceWindow = Window.get(byId: windowId)
    else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    _ = updatePendingWindowDragIntent(
        sourceWindow: sourceWindow,
        mouseLocation: mouseLocation,
        subject: getCurrentMouseDragSubject(),
        detachOrigin: getCurrentMouseTabDetachOrigin(),
    )
}

@MainActor
private func setPendingWindowDragIntent(sourceWindowId: UInt32, sourceSubject: WindowDragSubject, destination: WindowDragIntentDestination) -> Bool {
    if let pendingWindowDragIntent,
       pendingWindowDragIntent.sourceWindowId == sourceWindowId,
       pendingWindowDragIntent.sourceSubject == sourceSubject,
       pendingWindowDragIntent.kind == destination.kind,
       pendingWindowDragIntent.title == destination.title,
       pendingWindowDragIntent.subtitle == destination.subtitle,
       pendingWindowDragIntent.previewStyle == destination.previewStyle,
       pendingWindowDragIntent.previewGeometry == destination.previewGeometry,
       pendingWindowDragIntent.isGroup == destination.isGroup,
       pendingWindowDragIntent.previewRect.isEqual(to: destination.previewRect),
       pendingWindowDragIntent.interactionRect.isEqual(to: destination.interactionRect)
    {
        return true
    }

    let previousIntent = pendingWindowDragIntent
    pendingWindowDragIntent = PendingWindowDragIntent(
        sourceWindowId: sourceWindowId,
        sourceSubject: sourceSubject,
        kind: destination.kind,
        previewRect: destination.previewRect,
        interactionRect: destination.interactionRect,
        title: destination.title,
        subtitle: destination.subtitle,
        previewStyle: destination.previewStyle,
        previewGeometry: destination.previewGeometry,
        isGroup: destination.isGroup,
    )
    let signature =
        "intent:source=\(sourceWindowId):subject=\(debugDescribe(sourceSubject)):kind=\(debugDescribe(destination.kind)):preview=\(debugDescribe(destination.previewRect)):interaction=\(debugDescribe(destination.interactionRect))"
    logWindowDragIntentIfNeeded(
        signature: signature,
        "windowDragIntent.update mouse=\(debugDescribe(mouseLocation)) source=\(debugDescribe(Window.get(byId: sourceWindowId))) subject=\(debugDescribe(sourceSubject)) prevKind=\(previousIntent.map { debugDescribe($0.kind) } ?? "nil") prevPreview=\(debugDescribe(previousIntent?.previewRect)) newKind=\(debugDescribe(destination.kind)) newPreview=\(debugDescribe(destination.previewRect)) newInteraction=\(debugDescribe(destination.interactionRect)) style=\(destination.previewStyle) geometry=\(destination.previewGeometry)"
    )
    if destination.previewStyle == .sidebarWorkspaceMove {
        WindowTabDropPreviewPanel.shared.hide()
    } else {
        WindowTabDropPreviewPanel.shared.show(destination.preview(sourceWindowId: sourceWindowId))
    }
    return true
}

@MainActor
func clearPendingWindowDragIntent() {
    if let pendingWindowDragIntent {
        logWindowDragIntentIfNeeded(
            signature: "intent-cleared:source=\(pendingWindowDragIntent.sourceWindowId):kind=\(debugDescribe(pendingWindowDragIntent.kind))",
            "windowDragIntent.clear mouse=\(debugDescribe(mouseLocation)) source=\(debugDescribe(Window.get(byId: pendingWindowDragIntent.sourceWindowId))) kind=\(debugDescribe(pendingWindowDragIntent.kind)) preview=\(debugDescribe(pendingWindowDragIntent.previewRect))"
        )
    }
    pendingWindowDragIntent = nil
    lastWindowDragIntentLogSignature = nil
    setPinnedDraggedWindowId(nil)
    setWorkspaceSidebarDropPreviewIfChanged(nil)
    WindowTabDropPreviewPanel.shared.hide()
    WindowDragCursorProxyPanel.shared.hide()
}

@MainActor
func applyPendingWindowDragIntentIfPossible() -> Bool {
    defer { clearPendingWindowDragIntent() }
    guard let pendingWindowDragIntent,
          let sourceWindow = Window.get(byId: pendingWindowDragIntent.sourceWindowId),
          pendingWindowDragIntent.interactionRect.contains(mouseLocation),
          isWindowDragIntentKindEnabled(pendingWindowDragIntent.kind)
    else { return false }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: pendingWindowDragIntent.sourceSubject)
    switch pendingWindowDragIntent.kind {
        case .tabStack(let targetWindowId):
            guard pendingWindowDragIntent.sourceSubject == .window else { return false }
            guard let targetWindow = Window.get(byId: targetWindowId),
                  sourceWindow != targetWindow
            else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            createOrAppendWindowTabStack(sourceWindow: sourceWindow, onto: targetWindow)
            return true
        case .detachTab(let windowId):
            guard sourceWindow.windowId == windowId else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            return removeWindowFromTabStack(sourceWindow)
        case .stackSplit(let targetWindowId, let position):
            guard let targetWindow = Window.get(byId: targetWindowId)
            else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            return applyWindowStackSplitDragIntent(
                sourceWindow: sourceWindow,
                sourceSubject: pendingWindowDragIntent.sourceSubject,
                targetWindow: targetWindow,
                position: position,
            )
        case .swap(let targetWindowId):
            guard let targetWindow = Window.get(byId: targetWindowId)
            else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            return applyWindowSwapDragIntent(
                sourceWindow: sourceWindow,
                sourceSubject: pendingWindowDragIntent.sourceSubject,
                targetWindow: targetWindow,
            )
        case .moveToWorkspace(let workspaceName):
            guard let targetWorkspace = Workspace.existing(byName: workspaceName) else { return false }
            syncClosedWindowsCacheToCurrentWorld()
            if pendingWindowDragIntent.previewStyle == .sidebarWorkspaceMove {
                applySidebarWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, targetWorkspace: targetWorkspace)
            } else {
                applyWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, mouseLocation: mouseLocation, targetWorkspace: targetWorkspace)
            }
            return true
        case .createWorkspace:
            syncClosedWindowsCacheToCurrentWorld()
            return createWorkspaceFromSidebarDrag(sourceNode: sourceNode, sourceWindow: sourceWindow)
        case .sidebarHover:
            return false
    }
}

@MainActor
private struct WindowStackSplitContext {
    let insertionParent: TilingContainer?
    let anchorNode: TreeNode
    let wrapsTargetDirectly: Bool
}

@MainActor
private func windowStackSplitContext(
    targetNode: TreeNode,
    position: WindowStackSplitPosition,
) -> WindowStackSplitContext? {
    if let insertionParent = targetNode.parentsWithSelf
        .lazy
        .compactMap({ $0.parent as? TilingContainer })
        .first(where: { $0.layout == .tiles && $0.orientation == position.orientation }),
       let anchorNode = targetNode.directChild(in: insertionParent)
    {
        return WindowStackSplitContext(
            insertionParent: insertionParent,
            anchorNode: anchorNode,
            wrapsTargetDirectly: false,
        )
    }
    guard targetNode.parent is TilingContainer || targetNode.parent is Workspace else { return nil }
    return WindowStackSplitContext(
        insertionParent: targetNode.parent as? TilingContainer,
        anchorNode: targetNode,
        wrapsTargetDirectly: true,
    )
}

@MainActor
func canOfferWindowStackSplit(
    sourceNode: TreeNode,
    targetNode: TreeNode,
    position: WindowStackSplitPosition,
) -> Bool {
    windowStackSplitContext(targetNode: targetNode, position: position) != nil
}

@MainActor
func resolvedWindowStackSplitPreview(targetNode: TreeNode, position: WindowStackSplitPosition) -> WindowStackSplitPreview? {
    guard let splitContext = windowStackSplitContext(targetNode: targetNode, position: position) else { return nil }
    let referenceNode = splitContext.wrapsTargetDirectly ? targetNode : splitContext.anchorNode
    guard let referenceRect = referenceNode.windowDragVisibleRect,
          let previewRect = referenceRect.stackSplitPreviewRect(position: position)
    else { return nil }
    return WindowStackSplitPreview(
        rect: previewRect,
        geometry: position.previewGeometry,
    )
}

@MainActor
func applyWindowStackSplitDragIntent(
    sourceWindow: Window,
    sourceSubject: WindowDragSubject,
    targetWindow: Window,
    position: WindowStackSplitPosition,
) -> Bool {
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: sourceSubject)
    let targetNode = dragIntentTargetNode(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: sourceSubject,
        detachOrigin: getCurrentMouseTabDetachOrigin(),
    )
    let splitOrientation = position.orientation
    guard !isBlockedByDragTargetContainment(sourceNode: sourceNode, targetNode: targetNode),
          canOfferWindowStackSplit(sourceNode: sourceNode, targetNode: targetNode, position: position),
          let splitContext = windowStackSplitContext(targetNode: targetNode, position: position)
    else { return false }

    sourceNode.unbindFromParent()
    if !splitContext.wrapsTargetDirectly {
        guard let insertionParent = splitContext.insertionParent else { return false }
        let anchorBinding = splitContext.anchorNode.unbindFromParent()
        let splitWeight = anchorBinding.adaptiveWeight / 2
        if position.isPositive {
            splitContext.anchorNode.bind(to: insertionParent, adaptiveWeight: splitWeight, index: anchorBinding.index)
            sourceNode.bind(to: insertionParent, adaptiveWeight: splitWeight, index: anchorBinding.index + 1)
        } else {
            sourceNode.bind(to: insertionParent, adaptiveWeight: splitWeight, index: anchorBinding.index)
            splitContext.anchorNode.bind(to: insertionParent, adaptiveWeight: splitWeight, index: anchorBinding.index + 1)
        }
    } else {
        let targetBinding = targetNode.unbindFromParent()
        let newParent = TilingContainer(
            parent: targetBinding.parent,
            adaptiveWeight: targetBinding.adaptiveWeight,
            splitOrientation,
            .tiles,
            index: targetBinding.index,
        )
        if position.isPositive {
            targetNode.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
            sourceNode.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        } else {
            sourceNode.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
            targetNode.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
    }
    return sourceWindow.focusWindow()
}

@MainActor
func applyWindowSwapDragIntent(
    sourceWindow: Window,
    sourceSubject: WindowDragSubject,
    targetWindow: Window,
) -> Bool {
    if shouldSuppressSameAccordionSwapDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: sourceSubject,
        detachOrigin: getCurrentMouseTabDetachOrigin()
    ) {
        return false
    }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: sourceSubject)
    let targetNode = dragIntentTargetNode(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: sourceSubject,
        detachOrigin: getCurrentMouseTabDetachOrigin(),
    )
    guard !isBlockedByDragTargetContainment(sourceNode: sourceNode, targetNode: targetNode)
    else { return false }
    swapNodes(sourceNode, targetNode)
    return sourceWindow.focusWindow()
}

@MainActor
func createOrAppendWindowTabStack(sourceWindow: Window, onto targetWindow: Window) {
    guard sourceWindow != targetWindow else { return }
    if let targetParent = targetWindow.parent as? TilingContainer,
       targetParent.layout == .accordion
    {
        let targetIndex = targetWindow.ownIndex.orDie()
        let sourceIndex = sourceWindow.ownIndex
        let sourceWasInTargetParent = sourceWindow.parent === targetParent
        sourceWindow.unbindFromParent()
        let insertIndex = if sourceWasInTargetParent, let sourceIndex {
            sourceIndex < targetIndex ? targetIndex : targetIndex + 1
        } else {
            targetIndex + 1
        }
        sourceWindow.bind(to: targetParent, adaptiveWeight: WEIGHT_AUTO, index: insertIndex)
        sourceWindow.markAsMostRecentChild()
        _ = sourceWindow.focusWindow()
        return
    }

    let targetBinding = targetWindow.unbindFromParent()
    let newOrientation = (targetBinding.parent as? TilingContainer)?.orientation.opposite ?? .h
    let newParent = TilingContainer(
        parent: targetBinding.parent,
        adaptiveWeight: targetBinding.adaptiveWeight,
        newOrientation,
        .accordion,
        index: targetBinding.index,
    )
    sourceWindow.unbindFromParent()
    targetWindow.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
    sourceWindow.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    sourceWindow.markAsMostRecentChild()
    _ = sourceWindow.focusWindow()
}

@MainActor
@discardableResult
func removeWindowFromTabStack(_ window: Window) -> Bool {
    guard let parent = window.parent as? TilingContainer, parent.layout == .accordion else {
        return false
    }

    if let grandParent = parent.parent as? TilingContainer {
        window.unbindFromParent()
        if parent.children.count == 1 {
            let parentBinding = parent.unbindFromParent()
            let remainingChild = parent.children.singleOrNil().orDie()
            remainingChild.unbindFromParent()
            remainingChild.bind(to: grandParent, adaptiveWeight: parentBinding.adaptiveWeight, index: parentBinding.index)
            window.bind(to: grandParent, adaptiveWeight: WEIGHT_AUTO, index: parentBinding.index + 1)
        } else {
            let parentIndex = parent.ownIndex.orDie()
            window.bind(to: grandParent, adaptiveWeight: WEIGHT_AUTO, index: parentIndex + 1)
        }
        window.markAsMostRecentChild()
        _ = window.focusWindow()
        return true
    }

    guard parent.parent is Workspace else { return false }
    let remainingChildren = parent.children.filter { $0 != window }
    let accordionOrientation = parent.orientation

    window.unbindFromParent()
    let remainingMostRecentChild = parent.mostRecentChild
    parent.layout = .tiles
    parent.changeOrientation(accordionOrientation.opposite)

    if remainingChildren.count > 1 {
        let nestedAccordion = TilingContainer(
            parent: parent,
            adaptiveWeight: WEIGHT_AUTO,
            accordionOrientation,
            .accordion,
            index: 0,
        )
        for child in remainingChildren {
            child.unbindFromParent()
            child.bind(to: nestedAccordion, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
        remainingMostRecentChild?.markAsMostRecentChild()
    }

    window.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    window.markAsMostRecentChild()
    _ = window.focusWindow()
    return true
}

@MainActor
private func currentWindowDragIntentDestination(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    if let sidebarDestination = currentSidebarWorkspaceDropDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation, subject: subject) {
        return sidebarDestination
    }

    // Suppress window drop hints when the mouse is within the sidebar's
    // visible bounds during any drag — windows behind the sidebar
    // should never show hints since they're visually obscured.
    if let sidebarRect = WorkspaceSidebarPanel.shared.visibleScreenRectNormalized(),
       sidebarRect.contains(mouseLocation)
    {
        return nil
    }

    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    if targetWorkspace == sourceNode.nodeWorkspace,
       let surfaceDestination = currentWindowSurfaceDestination(
           sourceWindow: sourceWindow,
           mouseLocation: mouseLocation,
           subject: subject,
           detachOrigin: detachOrigin,
       )
    {
        return surfaceDestination
    }

    if let stickyDestination = currentStickyWindowDragIntentDestination(
        sourceWindow: sourceWindow,
        mouseLocation: mouseLocation,
        subject: subject,
        detachOrigin: detachOrigin,
    ) {
        return stickyDestination
    }

    if subject == .window,
       detachOrigin != .tabStrip,
       let detachDestination = currentTabDetachDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation, origin: detachOrigin)
    {
        return detachDestination
    }

    if targetWorkspace != sourceNode.nodeWorkspace {
        let previewRect = targetWorkspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        return WindowDragIntentDestination(
            kind: .moveToWorkspace(workspaceName: targetWorkspace.name),
            previewContainerRect: previewRect,
            previewRect: previewRect,
            interactionRect: previewRect,
            title: "Move Here",
            subtitle: "Drop to move this item to this workspace",
            previewStyle: .workspaceMove,
            previewGeometry: .rounded,
            isGroup: subject == .group,
        )
    }

    return nil
}

func shouldSuppressSwapDestination(sourceWindow: Window, subject: WindowDragSubject) -> Bool {
    subject == .window && sourceWindow.isFloating
}

@MainActor
private func applySidebarWorkspaceMove(sourceNode: TreeNode, sourceWindow: Window, targetWorkspace: Workspace) {
    if sourceNode is Window, sourceWindow.isFloating {
        sourceNode.bind(to: targetWorkspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    } else {
        let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
        sourceNode.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
    }
    _ = sourceWindow.focusWindow()
}

// Internal to keep cross-workspace insertion semantics unit-testable.
@MainActor
func applyWorkspaceMove(sourceNode: TreeNode, sourceWindow: Window, mouseLocation: CGPoint, targetWorkspace: Workspace) {
    if sourceNode is Window, sourceWindow.isFloating {
        sourceNode.bind(to: targetWorkspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        _ = sourceWindow.focusWindow()
        return
    }
    let swapTarget = mouseLocation.findIn(tree: targetWorkspace.rootTilingContainer, virtual: false)?.takeIf { $0.moveNode != sourceNode }
    let binding = workspaceMoveBindingData(
        targetWorkspace: targetWorkspace,
        swapTarget: swapTarget,
        mouseLocation: mouseLocation,
    )
    sourceNode.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
    _ = sourceWindow.focusWindow()
}

@MainActor
func workspaceMoveBindingData(
    targetWorkspace: Workspace,
    swapTarget: Window?,
    mouseLocation: CGPoint,
) -> BindingData {
    guard let swapTarget else {
        return workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
    }

    let targetNode = swapTarget.moveNode
    if let targetParent = targetNode.parent as? TilingContainer,
       let targetRect = targetNode.lastAppliedLayoutPhysicalRect
    {
        let index = mouseLocation.getProjection(targetParent.orientation) >= targetRect.center.getProjection(targetParent.orientation)
            ? targetNode.ownIndex.orDie() + 1
            : targetNode.ownIndex.orDie()
        return BindingData(
            parent: targetParent,
            adaptiveWeight: WEIGHT_AUTO,
            index: index,
        )
    }

    if targetNode === targetWorkspace.rootTilingContainer {
        let targetRect = targetNode.lastAppliedLayoutPhysicalRect ?? targetWorkspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        let insertionParent = workspaceSiblingInsertionRoot(targetWorkspace)
        let index = mouseLocation.getProjection(insertionParent.orientation) >= targetRect.center.getProjection(insertionParent.orientation)
            ? 1
            : 0
        return BindingData(
            parent: insertionParent,
            adaptiveWeight: WEIGHT_AUTO,
            index: index,
        )
    }

    return BindingData(
        parent: targetWorkspace.rootTilingContainer,
        adaptiveWeight: WEIGHT_AUTO,
        index: 0,
    )
}

@MainActor
func workspaceAppendBindingData(targetWorkspace: Workspace, index: Int) -> BindingData {
    BindingData(
        parent: workspaceSiblingInsertionRoot(targetWorkspace),
        adaptiveWeight: WEIGHT_AUTO,
        index: index,
    )
}

@MainActor
private func workspaceSiblingInsertionRoot(_ workspace: Workspace) -> TilingContainer {
    let root = workspace.rootTilingContainer
    guard root.layout == .accordion, !root.children.isEmpty else { return root }

    let previousRoot = root
    previousRoot.unbindFromParent()
    _ = TilingContainer(
        parent: workspace,
        adaptiveWeight: WEIGHT_AUTO,
        previousRoot.orientation.opposite,
        .tiles,
        index: 0,
    )
    previousRoot.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: 0)
    return workspace.rootTilingContainer
}

extension Rect {
    fileprivate func insetBy(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> Rect {
        Rect(
            topLeftX: topLeftX + left,
            topLeftY: topLeftY + top,
            width: width - left - right,
            height: height - top - bottom,
        )
    }

    fileprivate func expanded(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> Rect {
        insetBy(left: -left, right: -right, top: -top, bottom: -bottom)
    }

    fileprivate func expanded(by amount: CGFloat) -> Rect {
        Rect(topLeftX: topLeftX - amount, topLeftY: topLeftY - amount, width: width + 2 * amount, height: height + 2 * amount)
    }

    fileprivate func clampedPoint(_ point: CGPoint) -> CGPoint {
        let epsilon = CGFloat(0.001)
        return CGPoint(
            x: min(max(point.x, minX + epsilon), maxX - epsilon),
            y: min(max(point.y, minY + epsilon), maxY - epsilon),
        )
    }

    fileprivate func isEqual(to other: Rect) -> Bool {
        topLeftX == other.topLeftX && topLeftY == other.topLeftY && width == other.width && height == other.height
    }

    fileprivate var area: CGFloat {
        width * height
    }

    fileprivate func intersection(_ other: Rect) -> Rect {
        let minX = max(self.minX, other.minX)
        let minY = max(self.minY, other.minY)
        let maxX = min(self.maxX, other.maxX)
        let maxY = min(self.maxY, other.maxY)
        return Rect(
            topLeftX: minX,
            topLeftY: minY,
            width: max(maxX - minX, 0),
            height: max(maxY - minY, 0),
        )
    }

    fileprivate func isApproximatelyEqual(to other: Rect, tolerance: CGFloat) -> Bool {
        abs(topLeftX - other.topLeftX) <= tolerance &&
            abs(topLeftY - other.topLeftY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }

    fileprivate func stackSplitPreviewRect(position: WindowStackSplitPosition) -> Rect? {
        let rawRect = switch position {
            case .left:
                Rect(topLeftX: topLeftX, topLeftY: topLeftY, width: width / 2, height: height)
            case .right:
                Rect(topLeftX: topLeftX + width / 2, topLeftY: topLeftY, width: width / 2, height: height)
            case .above:
                Rect(topLeftX: topLeftX, topLeftY: topLeftY, width: width, height: height / 2)
            case .below:
                Rect(topLeftX: topLeftX, topLeftY: topLeftY + height / 2, width: width, height: height / 2)
        }
        let previewRect = switch position {
            case .left:
                rawRect.insetBy(left: windowDropPreviewInset, right: 0, top: windowDropPreviewInset, bottom: windowDropPreviewInset)
            case .right:
                rawRect.insetBy(left: 0, right: windowDropPreviewInset, top: windowDropPreviewInset, bottom: windowDropPreviewInset)
            case .above:
                rawRect.insetBy(left: windowDropPreviewInset, right: windowDropPreviewInset, top: windowDropPreviewInset, bottom: 0)
            case .below:
                rawRect.insetBy(left: windowDropPreviewInset, right: windowDropPreviewInset, top: 0, bottom: windowDropPreviewInset)
        }
        guard previewRect.width > 0, previewRect.height > 0 else { return nil }
        return previewRect
    }
}

extension TilingContainer {
    @MainActor
    var windowTabDropZoneRect: Rect? {
        guard showsWindowTabs, let rect = windowDragVisibleRect else { return nil }
        return rect.tabInsertPreviewRect(barHeight: windowTabBarHeight)
    }

    @MainActor
    var windowTabDropInteractionRect: Rect? {
        guard showsWindowTabs, let rect = windowDragVisibleRect else { return nil }
        return rect.tabInsertInteractionRect(barHeight: windowTabBarHeight)
    }
}

extension TreeNode {
    @MainActor
    private var centeredBodyDropZoneRect: Rect? {
        guard let rect = windowDragVisibleRect else { return nil }
        let topExclusion: CGFloat = switch self {
            case let window as Window:
                window.tabDropInteractionRect?.height ?? rect.height * 0.2
            case let container as TilingContainer:
                container.windowTabDropInteractionRect?.height ?? rect.height * 0.2
            default:
                max(rect.height * 0.2, 40)
        }
        let bodyRect = rect.insetBy(
            left: 2,
            right: 2,
            top: min(topExclusion, rect.height * 0.45),
            bottom: 2,
        )
        guard bodyRect.width > 0, bodyRect.height > 0 else { return nil }
        return bodyRect
    }

    @MainActor
    private var sideBodyDropZoneRect: Rect? {
        guard let rect = windowDragVisibleRect else { return nil }
        let bodyRect = rect.insetBy(left: 2, right: 2, top: 2, bottom: 2)
        guard bodyRect.width > 0, bodyRect.height > 0 else { return nil }
        return bodyRect
    }

    @MainActor
    func bodyDragIntent(at mouseLocation: CGPoint) -> WindowBodyDragIntent? {
        guard let swapRect = swapDropZoneRect else { return nil }
        if swapRect.contains(mouseLocation) {
            return .swap
        }
        for position in [WindowStackSplitPosition.left, .right, .above, .below] {
            if stackSplitDropZoneRect(position: position)?.contains(mouseLocation) == true {
                return .stackSplit(position)
            }
        }
        return nil
    }

    @MainActor
    func stackSplitDropZoneRect(position: WindowStackSplitPosition) -> Rect? {
        guard let centeredBodyRect = centeredBodyDropZoneRect,
              let sideBodyRect = sideBodyDropZoneRect,
              let swapRect = swapDropZoneRect
        else { return nil }
        return switch position {
            case .left:
                (swapRect.minX > sideBodyRect.minX)
                    ? Rect(
                        topLeftX: sideBodyRect.topLeftX,
                        topLeftY: sideBodyRect.topLeftY,
                        width: swapRect.minX - sideBodyRect.minX,
                        height: sideBodyRect.height,
                    )
                    : nil
            case .right:
                (sideBodyRect.maxX > swapRect.maxX)
                    ? Rect(
                        topLeftX: swapRect.maxX,
                        topLeftY: sideBodyRect.topLeftY,
                        width: sideBodyRect.maxX - swapRect.maxX,
                        height: sideBodyRect.height,
                    )
                    : nil
            case .above:
                (swapRect.minY > centeredBodyRect.minY)
                    ? Rect(
                        topLeftX: swapRect.topLeftX,
                        topLeftY: centeredBodyRect.topLeftY,
                        width: swapRect.width,
                        height: swapRect.minY - centeredBodyRect.minY,
                    )
                    : nil
            case .below:
                (centeredBodyRect.maxY > swapRect.maxY)
                    ? Rect(
                        topLeftX: swapRect.topLeftX,
                        topLeftY: swapRect.maxY,
                        width: swapRect.width,
                        height: centeredBodyRect.maxY - swapRect.maxY,
                    )
                    : nil
        }
    }

    @MainActor
    func stackSplitPreviewRect(position: WindowStackSplitPosition) -> Rect? {
        windowDragVisibleRect?.stackSplitPreviewRect(position: position)
    }

    @MainActor
    var swapDropZoneRect: Rect? {
        guard let bodyRect = centeredBodyDropZoneRect else { return nil }
        let swapWidth = min(bodyRect.width, max(bodyRect.width * 0.2, 28))
        let swapHeight = min(bodyRect.height, max(bodyRect.height * 0.2, 28))
        let swapRect = Rect(
            topLeftX: bodyRect.topLeftX + (bodyRect.width - swapWidth) / 2,
            topLeftY: bodyRect.topLeftY + (bodyRect.height - swapHeight) / 2,
            width: swapWidth,
            height: swapHeight,
        )
        guard swapRect.width > 0, swapRect.height > 0 else { return nil }
        return swapRect
    }
}

extension Rect {
    fileprivate func tabInsertPreviewRect(barHeight: CGFloat) -> Rect {
        // Reserve a visibly taller top strip so the tab-insert affordance
        // wins reliably over body intents, even on angled approaches.
        let effectiveHeight = min(
            max(barHeight + windowTabInsertPreviewExtraHeight, windowTabInsertPreviewMinHeight),
            max(height, 0)
        )
        return insetBy(
            left: windowDropPreviewInset,
            right: windowDropPreviewInset,
            top: windowDropPreviewInset,
            bottom: max(height - effectiveHeight, 0),
        )
    }

    fileprivate func tabInsertInteractionRect(barHeight: CGFloat) -> Rect {
        tabInsertPreviewRect(barHeight: barHeight).expanded(
            left: windowTabInsertInteractionHorizontalInset,
            right: windowTabInsertInteractionHorizontalInset,
            top: windowTabInsertInteractionTopInset,
            bottom: windowTabInsertInteractionBottomInset
        )
    }
}
