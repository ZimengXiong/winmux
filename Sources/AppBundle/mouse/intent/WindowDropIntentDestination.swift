import CoreGraphics

@MainActor
func destinationFromWindowDropIntent(
    _ resolution: WindowDropIntentResolution,
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    func intentOverlayDestination(_ destination: WindowDragIntentDestination) -> WindowDragIntentDestination {
        var result = destination
        result.previewRect = windowDropIntentActivePreviewRect(for: resolution)
        result.interactionRect = resolution.targetFrame
        result.dropIntentOverlay = WindowDropIntentOverlayModel(
            targetFrame: resolution.targetFrame,
            activeZone: resolution.intent.zone,
            cornerRadius: resolution.targetCornerRadius.map(CGFloat.init)
        )
        return result
    }

    switch resolution.intent.zone {
        case .tab:
            guard config.windowTabs.enabled,
                  isWindowDragIntentKindEnabled(.tabStack(targetWindowId: targetWindow.windowId)),
                  !shouldSuppressSameTabGroupTabDestination(
                      sourceWindow: sourceWindow,
                      targetWindow: targetWindow,
                      detachOrigin: detachOrigin
                  )
            else { return nil }
            return intentOverlayDestination(WindowDragIntentDestination(
                kind: .tabStack(targetWindowId: targetWindow.windowId),
                previewRect: windowDropIntentActivePreviewRect(for: resolution),
                interactionRect: resolution.targetFrame,
                title: "Insert Into Tabs",
                subtitle: "Drop in the top zone to add this window",
                previewStyle: .tabInsert,
                previewGeometry: .tabStrip,
                isGroup: false,
            ))
        case .middle:
            guard let destination = swapDestination(
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                detachOrigin: detachOrigin,
            ) else { return nil }
            return intentOverlayDestination(destination)
        case .left, .right, .top, .bottom:
            guard let position = resolution.intent.zone.stackSplitPosition else { return nil }
            guard let destination = stackSplitDestination(
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                position: position,
                detachOrigin: detachOrigin,
            ) else { return nil }
            return intentOverlayDestination(destination)
    }
}

func windowDropIntentActivePreviewRect(for resolution: WindowDropIntentResolution) -> Rect {
    resolution.zones.first { $0.zone == resolution.intent.zone }?.frame ?? resolution.targetFrame
}

@MainActor
func resolveWindowDropIntent(
    sourceWindow: Window,
    targetWindow: Window,
    targetNode: TreeNode,
    mouseLocation: CGPoint,
) -> WindowDropIntentResolution? {
    guard let targetFrame = targetNode.windowDragVisibleRect else { return nil }
    return WindowDropIntentResolver().resolve(
        sourceWindowId: sourceWindow.windowId,
        targetWindowId: targetWindow.windowId,
        pointer: mouseLocation,
        targetFrame: targetFrame,
    )
}
