import AppKit

@MainActor
func tabStackDestination(targetWindow: Window, mouseLocation: CGPoint? = nil) -> WindowDragIntentDestination? {
    guard isWindowDragIntentKindEnabled(.tabStack(targetWindowId: targetWindow.windowId)),
          let rects = targetWindow.tabStackTargetRects,
          mouseLocation.map(rects.interactionRect.contains) ?? true
    else { return nil }
    return WindowDragIntentDestination(
        kind: .tabStack(targetWindowId: targetWindow.windowId),
        previewRect: rects.previewRect,
        interactionRect: rects.interactionRect,
        title: "Insert Into Tabs",
        subtitle: "Drop near the top edge to add this window",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
    )
}

@MainActor
func selfTabGroupTabReentryDestination(
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
          sourceParent.layout == .tabGroup,
          let targetFrame = sourceParent.windowDragVisibleRect,
          targetWindow.parent === sourceParent,
          let previewRect = sourceParent.windowTabDropZoneRect,
          let interactionRect = sourceParent.windowTabDropInteractionRect,
          interactionRect.contains(mouseLocation)
    else { return nil }
    let sourceIndex = sourceWindow.ownIndex ?? 0
    let targetIndex = tabReentryTargetIndex(
        mouseLocation: mouseLocation,
        tabStripRect: previewRect,
        tabCount: sourceParent.children.count,
        sourceIndex: sourceIndex
    )

    return WindowDragIntentDestination(
        kind: .reorderTab(windowId: sourceWindow.windowId, targetIndex: targetIndex),
        previewRect: previewRect,
        interactionRect: interactionRect,
        title: "Return To Tabs",
        subtitle: "Drop to cancel the detach and put this tab back in the group",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
        dropIntentOverlay: WindowDropIntentOverlayModel(
            targetFrame: targetFrame,
            activeZone: .tab,
            cornerRadius: nil,
        ),
    )
}

func tabReentryTargetIndex(
    mouseLocation: CGPoint,
    tabStripRect: Rect,
    tabCount: Int,
    sourceIndex: Int? = nil,
) -> Int {
    guard tabCount > 1, tabStripRect.width > 0 else { return 0 }
    let tabWidth = windowTabStripTabWidth(stripWidth: tabStripRect.width, count: tabCount)
    let effectiveTabWidth = tabWidth + windowTabStripTabSpacing
    let firstTabMinX = tabStripRect.minX + windowTabStripContentHorizontalPadding
    let localX = mouseLocation.x - firstTabMinX
    let hoveredTabIndex = max(0, min(Int(floor(localX / effectiveTabWidth)), tabCount - 1))
    let hoveredTabCenterX = firstTabMinX + CGFloat(hoveredTabIndex) * effectiveTabWidth + tabWidth / 2
    let insertionSlot = hoveredTabIndex + (mouseLocation.x >= hoveredTabCenterX ? 1 : 0)
    guard let sourceIndex else {
        return max(0, min(insertionSlot, tabCount - 1))
    }
    let adjustedTarget = insertionSlot > sourceIndex ? insertionSlot - 1 : insertionSlot
    return max(0, min(adjustedTarget, tabCount - 1))
}

func tabReentrySourceVisualOffset(
    mouseLocation: CGPoint,
    tabStripRect: Rect,
    tabCount: Int,
    sourceIndex: Int,
) -> CGFloat {
    guard tabCount > 1, tabStripRect.width > 0 else { return 0 }
    let tabWidth = windowTabStripTabWidth(stripWidth: tabStripRect.width, count: tabCount)
    let effectiveTabWidth = tabWidth + windowTabStripTabSpacing
    let sourceCenterX = tabStripRect.minX
        + windowTabStripContentHorizontalPadding
        + CGFloat(sourceIndex) * effectiveTabWidth
        + tabWidth / 2
    let minOffset = -CGFloat(sourceIndex) * effectiveTabWidth
    let maxOffset = CGFloat(max(tabCount - 1 - sourceIndex, 0)) * effectiveTabWidth
    return max(min(mouseLocation.x - sourceCenterX, maxOffset), minOffset)
}
