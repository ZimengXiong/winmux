import AppKit
import Common
import SwiftUI

enum UnmanagedWindowSnapAction: String, CaseIterable, Sendable {
    case leftHalf = "left-half"
    case rightHalf = "right-half"
    case topHalf = "top-half"
    case bottomHalf = "bottom-half"
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
    case firstThird = "first-third"
    case centerThird = "center-third"
    case lastThird = "last-third"
    case firstTwoThirds = "first-two-thirds"
    case lastTwoThirds = "last-two-thirds"
    case maximize

    var previewTitle: String {
        switch self {
            case .leftHalf: "Left Half"
            case .rightHalf: "Right Half"
            case .topHalf: "Top Half"
            case .bottomHalf: "Bottom Half"
            case .topLeft: "Top Left"
            case .topRight: "Top Right"
            case .bottomLeft: "Bottom Left"
            case .bottomRight: "Bottom Right"
            case .firstThird: "First Third"
            case .centerThird: "Center Third"
            case .lastThird: "Last Third"
            case .firstTwoThirds: "First Two Thirds"
            case .lastTwoThirds: "Last Two Thirds"
            case .maximize: "Maximize"
        }
    }
}

private enum UnmanagedSnapDirectional {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight
}

private struct PendingUnmanagedWindowSnap: Equatable {
    let windowId: UInt32
    let workspaceName: String
    let action: UnmanagedWindowSnapAction
    let containerRect: Rect
    let targetRect: Rect

    static func == (lhs: PendingUnmanagedWindowSnap, rhs: PendingUnmanagedWindowSnap) -> Bool {
        lhs.windowId == rhs.windowId &&
            lhs.workspaceName == rhs.workspaceName &&
            lhs.action == rhs.action &&
            lhs.containerRect.topLeftX == rhs.containerRect.topLeftX &&
            lhs.containerRect.topLeftY == rhs.containerRect.topLeftY &&
            lhs.containerRect.width == rhs.containerRect.width &&
            lhs.containerRect.height == rhs.containerRect.height &&
            lhs.targetRect.topLeftX == rhs.targetRect.topLeftX &&
            lhs.targetRect.topLeftY == rhs.targetRect.topLeftY &&
            lhs.targetRect.width == rhs.targetRect.width &&
            lhs.targetRect.height == rhs.targetRect.height
    }
}

private let rectangleSnapEdgeMargin: CGFloat = 5
private let rectangleSnapCornerSize: CGFloat = 20
private let unmanagedSnapMaximizeCenterFraction: CGFloat = 1.0 / 3.0

@MainActor private var pendingUnmanagedWindowSnap: PendingUnmanagedWindowSnap? = nil
@MainActor private var lastUnmanagedWindowSnapLogSignature: String? = nil


private func debugDescribeUnmanagedSnap(_ rect: Rect?) -> String {
    guard let rect else { return "nil" }
    return "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height)))"
}

private func debugDescribeUnmanagedSnap(_ point: CGPoint) -> String {
    "(\(Int(point.x)),\(Int(point.y)))"
}

private func debugDescribeUnmanagedSnap(_ action: UnmanagedWindowSnapAction?) -> String {
    action?.rawValue ?? "nil"
}

@MainActor
private func logUnmanagedWindowSnapIfNeeded(signature: String, _ message: @autoclosure () -> String) {
    guard lastUnmanagedWindowSnapLogSignature != signature else { return }
    lastUnmanagedWindowSnapLogSignature = signature
    debugFocusLog(message())
}

private func rectContainsInclusive(_ rect: Rect, _ point: CGPoint) -> Bool {
    point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
}

private func unmanagedSnapDirectional(at mouseLocation: CGPoint, in detectionRect: Rect) -> UnmanagedSnapDirectional? {
    guard rectContainsInclusive(detectionRect, mouseLocation) else { return nil }

    let leftEdge = detectionRect.minX + rectangleSnapEdgeMargin
    let rightEdge = detectionRect.maxX - rectangleSnapEdgeMargin
    let topEdge = detectionRect.minY + rectangleSnapEdgeMargin
    let bottomEdge = detectionRect.maxY - rectangleSnapEdgeMargin

    // Borrow Rectangle's snap-area entry logic directly: corners extend past the
    // edge margin, but side / top / bottom snaps only activate once the cursor
    // actually reaches the configured screen edge band.
    if mouseLocation.x < leftEdge + rectangleSnapCornerSize {
        if mouseLocation.y <= topEdge + rectangleSnapCornerSize {
            return .topLeft
        }
        if mouseLocation.y >= bottomEdge - rectangleSnapCornerSize {
            return .bottomLeft
        }
        if mouseLocation.x < leftEdge {
            return .left
        }
    }

    if mouseLocation.x > rightEdge - rectangleSnapCornerSize {
        if mouseLocation.y <= topEdge + rectangleSnapCornerSize {
            return .topRight
        }
        if mouseLocation.y >= bottomEdge - rectangleSnapCornerSize {
            return .bottomRight
        }
        if mouseLocation.x > rightEdge {
            return .right
        }
    }

    if mouseLocation.y < topEdge {
        return .top
    }
    if mouseLocation.y > bottomEdge {
        return .bottom
    }

    return nil
}

private func unmanagedTopEdgeAction(mouseLocation: CGPoint, detectionRect: Rect) -> UnmanagedWindowSnapAction {
    let centerWidth = detectionRect.width * unmanagedSnapMaximizeCenterFraction
    let centerMinX = detectionRect.minX + (detectionRect.width - centerWidth) / 2
    let centerMaxX = centerMinX + centerWidth
    return (centerMinX ... centerMaxX).contains(mouseLocation.x) ? .maximize : .topHalf
}

private func unmanagedVerticalEdgeAction(mouseLocation: CGPoint, detectionRect: Rect, fallback: UnmanagedWindowSnapAction) -> UnmanagedWindowSnapAction {
    let firstThirdMaxY = detectionRect.minY + detectionRect.height / 3
    let lastThirdMinY = detectionRect.minY + detectionRect.height * 2 / 3
    if mouseLocation.y < firstThirdMaxY {
        return .topHalf
    }
    if mouseLocation.y > lastThirdMinY {
        return .bottomHalf
    }
    return fallback
}

private func unmanagedBottomEdgeAction(
    mouseLocation: CGPoint,
    detectionRect: Rect,
    priorAction: UnmanagedWindowSnapAction?,
) -> UnmanagedWindowSnapAction {
    if detectionRect.height > detectionRect.width {
        let centerX = detectionRect.minX + detectionRect.width / 2
        return mouseLocation.x < centerX ? .leftHalf : .rightHalf
    }

    let firstThirdMaxX = detectionRect.minX + detectionRect.width / 3
    let lastThirdMinX = detectionRect.minX + detectionRect.width * 2 / 3
    if mouseLocation.x < firstThirdMaxX {
        return .firstThird
    }
    if mouseLocation.x > lastThirdMinX {
        return .lastThird
    }

    return switch priorAction {
        case .firstThird: .firstTwoThirds
        case .lastThird: .lastTwoThirds
        default: .centerThird
    }
}

func unmanagedSnapAction(
    at mouseLocation: CGPoint,
    in detectionRect: Rect,
    priorAction: UnmanagedWindowSnapAction?,
) -> UnmanagedWindowSnapAction? {
    guard let directional = unmanagedSnapDirectional(at: mouseLocation, in: detectionRect) else { return nil }

    switch directional {
        case .topLeft:
            return .topLeft
        case .top:
            return unmanagedTopEdgeAction(mouseLocation: mouseLocation, detectionRect: detectionRect)
        case .topRight:
            return .topRight
        case .left:
            return unmanagedVerticalEdgeAction(mouseLocation: mouseLocation, detectionRect: detectionRect, fallback: .leftHalf)
        case .right:
            return unmanagedVerticalEdgeAction(mouseLocation: mouseLocation, detectionRect: detectionRect, fallback: .rightHalf)
        case .bottomLeft:
            return .bottomLeft
        case .bottom:
            return unmanagedBottomEdgeAction(mouseLocation: mouseLocation, detectionRect: detectionRect, priorAction: priorAction)
        case .bottomRight:
            return .bottomRight
    }
}

func unmanagedSnapTargetRect(for action: UnmanagedWindowSnapAction, in workspaceRect: Rect) -> Rect {
    func rect(xFraction: CGFloat, yFraction: CGFloat, widthFraction: CGFloat, heightFraction: CGFloat) -> Rect {
        Rect(
            topLeftX: workspaceRect.topLeftX + workspaceRect.width * xFraction,
            topLeftY: workspaceRect.topLeftY + workspaceRect.height * yFraction,
            width: workspaceRect.width * widthFraction,
            height: workspaceRect.height * heightFraction,
        )
    }

    let usesHorizontalThirds = workspaceRect.width >= workspaceRect.height
    switch action {
        case .leftHalf:
            return rect(xFraction: 0, yFraction: 0, widthFraction: 0.5, heightFraction: 1)
        case .rightHalf:
            return rect(xFraction: 0.5, yFraction: 0, widthFraction: 0.5, heightFraction: 1)
        case .topHalf:
            return rect(xFraction: 0, yFraction: 0, widthFraction: 1, heightFraction: 0.5)
        case .bottomHalf:
            return rect(xFraction: 0, yFraction: 0.5, widthFraction: 1, heightFraction: 0.5)
        case .topLeft:
            return rect(xFraction: 0, yFraction: 0, widthFraction: 0.5, heightFraction: 0.5)
        case .topRight:
            return rect(xFraction: 0.5, yFraction: 0, widthFraction: 0.5, heightFraction: 0.5)
        case .bottomLeft:
            return rect(xFraction: 0, yFraction: 0.5, widthFraction: 0.5, heightFraction: 0.5)
        case .bottomRight:
            return rect(xFraction: 0.5, yFraction: 0.5, widthFraction: 0.5, heightFraction: 0.5)
        case .firstThird:
            return usesHorizontalThirds
                ? rect(xFraction: 0, yFraction: 0, widthFraction: 1.0 / 3.0, heightFraction: 1)
                : rect(xFraction: 0, yFraction: 0, widthFraction: 1, heightFraction: 1.0 / 3.0)
        case .centerThird:
            return usesHorizontalThirds
                ? rect(xFraction: 1.0 / 3.0, yFraction: 0, widthFraction: 1.0 / 3.0, heightFraction: 1)
                : rect(xFraction: 0, yFraction: 1.0 / 3.0, widthFraction: 1, heightFraction: 1.0 / 3.0)
        case .lastThird:
            return usesHorizontalThirds
                ? rect(xFraction: 2.0 / 3.0, yFraction: 0, widthFraction: 1.0 / 3.0, heightFraction: 1)
                : rect(xFraction: 0, yFraction: 2.0 / 3.0, widthFraction: 1, heightFraction: 1.0 / 3.0)
        case .firstTwoThirds:
            return usesHorizontalThirds
                ? rect(xFraction: 0, yFraction: 0, widthFraction: 2.0 / 3.0, heightFraction: 1)
                : rect(xFraction: 0, yFraction: 0, widthFraction: 1, heightFraction: 2.0 / 3.0)
        case .lastTwoThirds:
            return usesHorizontalThirds
                ? rect(xFraction: 1.0 / 3.0, yFraction: 0, widthFraction: 2.0 / 3.0, heightFraction: 1)
                : rect(xFraction: 0, yFraction: 1.0 / 3.0, widthFraction: 1, heightFraction: 2.0 / 3.0)
        case .maximize:
            return workspaceRect
    }
}

@MainActor
private func setPendingUnmanagedWindowSnap(_ pending: PendingUnmanagedWindowSnap) {
    guard pendingUnmanagedWindowSnap != pending else { return }
    logUnmanagedWindowSnapIfNeeded(
        signature: "set:\(pending.windowId):\(pending.workspaceName):\(pending.action.rawValue):\(debugDescribeUnmanagedSnap(pending.targetRect))",
        "unmanagedSnap.set window=\(pending.windowId) workspace=\(pending.workspaceName) action=\(pending.action.rawValue) container=\(debugDescribeUnmanagedSnap(pending.containerRect)) target=\(debugDescribeUnmanagedSnap(pending.targetRect))"
    )
    pendingUnmanagedWindowSnap = pending
    UnmanagedWindowSnapPreviewPanel.shared.show(action: pending.action, frame: pending.targetRect.toAppKitScreenRect)
}

@MainActor
func clearPendingUnmanagedWindowSnap(reason: String? = nil) {
    guard let pending = pendingUnmanagedWindowSnap else { return }
    logUnmanagedWindowSnapIfNeeded(
        signature: "clear:\(pending.windowId):\(pending.workspaceName):\(pending.action.rawValue):\(reason ?? "unspecified")",
        "unmanagedSnap.clear window=\(pending.windowId) workspace=\(pending.workspaceName) action=\(pending.action.rawValue) reason=\(reason ?? "unspecified")"
    )
    pendingUnmanagedWindowSnap = nil
    UnmanagedWindowSnapPreviewPanel.shared.hide()
}

@MainActor
func refreshPendingUnmanagedWindowSnap(sourceWindow: Window, mouseLocation: CGPoint) {
    guard !config.enableWindowManagement else {
        clearPendingUnmanagedWindowSnap(reason: "managed-mode-enabled")
        return
    }
    let workspace = mouseLocation.monitorApproximation.activeWorkspace
    let detectionRect = workspace.workspaceMonitor.visibleRect
    let targetRect = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
    let priorAction = pendingUnmanagedWindowSnap.flatMap { pending in
        (pending.windowId == sourceWindow.windowId && pending.workspaceName == workspace.name)
            ? pending.action
            : nil
    }
    guard let action = unmanagedSnapAction(at: mouseLocation, in: detectionRect, priorAction: priorAction) else {
        logUnmanagedWindowSnapIfNeeded(
            signature: "resolve:none:\(sourceWindow.windowId):\(workspace.name):\(debugDescribeUnmanagedSnap(mouseLocation))",
            "unmanagedSnap.resolve window=\(sourceWindow.windowId) workspace=\(workspace.name) mouse=\(debugDescribeUnmanagedSnap(mouseLocation)) prior=\(debugDescribeUnmanagedSnap(priorAction)) action=nil detection=\(debugDescribeUnmanagedSnap(detectionRect)) target=\(debugDescribeUnmanagedSnap(targetRect))"
        )
        clearPendingUnmanagedWindowSnap(reason: "no-snap-action")
        return
    }
    let resolvedTargetRect = unmanagedSnapTargetRect(for: action, in: targetRect)
    logUnmanagedWindowSnapIfNeeded(
        signature: "resolve:\(sourceWindow.windowId):\(workspace.name):\(action.rawValue):\(debugDescribeUnmanagedSnap(resolvedTargetRect))",
        "unmanagedSnap.resolve window=\(sourceWindow.windowId) workspace=\(workspace.name) mouse=\(debugDescribeUnmanagedSnap(mouseLocation)) prior=\(debugDescribeUnmanagedSnap(priorAction)) action=\(action.rawValue) detection=\(debugDescribeUnmanagedSnap(detectionRect)) target=\(debugDescribeUnmanagedSnap(resolvedTargetRect))"
    )
    setPendingUnmanagedWindowSnap(PendingUnmanagedWindowSnap(
        windowId: sourceWindow.windowId,
        workspaceName: workspace.name,
        action: action,
        containerRect: targetRect,
        targetRect: resolvedTargetRect,
    ))
}

@MainActor
func refreshPendingUnmanagedWindowSnapFromGlobalMouseDrag() {
    guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .move else {
        clearPendingUnmanagedWindowSnap(reason: "inactive-global-drag")
        return
    }
    guard let windowId = currentlyManipulatedWithMouseWindowId,
          let sourceWindow = Window.get(byId: windowId)
    else {
        clearPendingUnmanagedWindowSnap(reason: "missing-source-window")
        cancelManipulatedWithMouseState()
        return
    }
    refreshPendingUnmanagedWindowSnap(sourceWindow: sourceWindow, mouseLocation: mouseLocation)
}

@MainActor
func applyPendingUnmanagedWindowSnapIfPossible() -> Bool {
    defer { clearPendingUnmanagedWindowSnap() }
    guard let pendingUnmanagedWindowSnap,
          let window = Window.get(byId: pendingUnmanagedWindowSnap.windowId)
    else {
        logUnmanagedWindowSnapIfNeeded(
            signature: "apply:missing",
            "unmanagedSnap.apply pending=nil-or-window-missing"
        )
        return false
    }
    logUnmanagedWindowSnapIfNeeded(
        signature: "apply:\(pendingUnmanagedWindowSnap.windowId):\(pendingUnmanagedWindowSnap.workspaceName):\(pendingUnmanagedWindowSnap.action.rawValue):\(debugDescribeUnmanagedSnap(pendingUnmanagedWindowSnap.targetRect))",
        "unmanagedSnap.apply window=\(pendingUnmanagedWindowSnap.windowId) workspace=\(pendingUnmanagedWindowSnap.workspaceName) action=\(pendingUnmanagedWindowSnap.action.rawValue) target=\(debugDescribeUnmanagedSnap(pendingUnmanagedWindowSnap.targetRect))"
    )
    window.lastFloatingSize = pendingUnmanagedWindowSnap.targetRect.size
    window.lastKnownActualRect = pendingUnmanagedWindowSnap.targetRect
    window.setAxFrame(pendingUnmanagedWindowSnap.targetRect.topLeftCorner, pendingUnmanagedWindowSnap.targetRect.size)
    return true
}
