import AppKit
import Common

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

    guard let intentReferenceRect = stickyReferenceRect(targetWindow: targetWindow, previewStyle: sticky.previewStyle) else { return nil }
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
