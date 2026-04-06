import AppKit
import Common

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
private let unmanagedSnapPreviewBorderWidth: CGFloat = 3
private let unmanagedSnapPreviewCornerRadius: CGFloat = 10
private let unmanagedSnapPreviewFillOpacity: CGFloat = 0.08

@MainActor private var pendingUnmanagedWindowSnap: PendingUnmanagedWindowSnap? = nil
@MainActor private var lastUnmanagedWindowSnapLogSignature: String? = nil

private func alignedUnmanagedSnapPreviewFrame(_ frame: CGRect) -> CGRect {
    let scale = (
        NSScreen.screens.max(by: { $0.frame.intersection(frame).width * $0.frame.intersection(frame).height <
            $1.frame.intersection(frame).width * $1.frame.intersection(frame).height
        })?.backingScaleFactor ??
            NSScreen.main?.backingScaleFactor ??
            2
    )
    let alignedMinX = (frame.minX * scale).rounded() / scale
    let alignedMinY = (frame.minY * scale).rounded() / scale
    let alignedMaxX = (frame.maxX * scale).rounded() / scale
    let alignedMaxY = (frame.maxY * scale).rounded() / scale
    return CGRect(
        x: alignedMinX,
        y: alignedMinY,
        width: max(alignedMaxX - alignedMinX, 0),
        height: max(alignedMaxY - alignedMinY, 0),
    )
}

@MainActor
private final class UnmanagedWindowSnapPreviewPanel: NSPanelHud {
    static let shared = UnmanagedWindowSnapPreviewPanel()

    private let overlayView = NSView(frame: .zero)
    private var pendingHide: DispatchWorkItem? = nil
    private let hideDebounce: TimeInterval = 0.07

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier("unmanagedWindowSnapPreviewPanel")
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        level = .statusBar
        backgroundColor = .clear

        overlayView.wantsLayer = true
        overlayView.layer?.masksToBounds = true
        overlayView.layer?.cornerRadius = unmanagedSnapPreviewCornerRadius
        overlayView.layer?.borderWidth = unmanagedSnapPreviewBorderWidth
        contentView = overlayView
        applyStyle()
    }

    func show(frame: CGRect) {
        pendingHide?.cancel()
        pendingHide = nil
        applyStyle()
        let targetFrame = alignedUnmanagedSnapPreviewFrame(frame)
        if self.frame != targetFrame {
            setFrame(targetFrame, display: true, animate: false)
        }
        orderFrontRegardless()
    }

    func hide() {
        pendingHide?.cancel()
        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            self.orderOut(nil)
        }
        pendingHide = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDebounce, execute: hideWorkItem)
    }

    private func applyStyle() {
        let accent = NSColor.controlAccentColor
        overlayView.layer?.backgroundColor = accent.withAlphaComponent(unmanagedSnapPreviewFillOpacity).cgColor
        overlayView.layer?.borderColor = accent.cgColor
    }
}

private func debugDescribe(_ rect: Rect) -> String {
    "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height)))"
}

private func debugDescribe(_ rect: Rect?) -> String {
    guard let rect else { return "nil" }
    return debugDescribe(rect)
}

private func debugDescribe(_ point: CGPoint) -> String {
    "(\(Int(point.x)),\(Int(point.y)))"
}

private func debugDescribe(_ action: UnmanagedWindowSnapAction?) -> String {
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
            return .leftHalf
        case .right:
            return .rightHalf
        case .bottomLeft:
            return .bottomLeft
        case .bottom:
            return .bottomHalf
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
        signature: "set:\(pending.windowId):\(pending.workspaceName):\(pending.action.rawValue):\(debugDescribe(pending.targetRect))",
        "unmanagedSnap.set window=\(pending.windowId) workspace=\(pending.workspaceName) action=\(pending.action.rawValue) container=\(debugDescribe(pending.containerRect)) target=\(debugDescribe(pending.targetRect))"
    )
    pendingUnmanagedWindowSnap = pending
    UnmanagedWindowSnapPreviewPanel.shared.show(frame: pending.targetRect.toAppKitScreenRect)
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
            signature: "resolve:none:\(sourceWindow.windowId):\(workspace.name):\(debugDescribe(mouseLocation))",
            "unmanagedSnap.resolve window=\(sourceWindow.windowId) workspace=\(workspace.name) mouse=\(debugDescribe(mouseLocation)) prior=\(debugDescribe(priorAction)) action=nil detection=\(debugDescribe(detectionRect)) target=\(debugDescribe(targetRect))"
        )
        clearPendingUnmanagedWindowSnap(reason: "no-snap-action")
        return
    }
    let resolvedTargetRect = unmanagedSnapTargetRect(for: action, in: targetRect)
    logUnmanagedWindowSnapIfNeeded(
        signature: "resolve:\(sourceWindow.windowId):\(workspace.name):\(action.rawValue):\(debugDescribe(resolvedTargetRect))",
        "unmanagedSnap.resolve window=\(sourceWindow.windowId) workspace=\(workspace.name) mouse=\(debugDescribe(mouseLocation)) prior=\(debugDescribe(priorAction)) action=\(action.rawValue) detection=\(debugDescribe(detectionRect)) target=\(debugDescribe(resolvedTargetRect))"
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
        signature: "apply:\(pendingUnmanagedWindowSnap.windowId):\(pendingUnmanagedWindowSnap.workspaceName):\(pendingUnmanagedWindowSnap.action.rawValue):\(debugDescribe(pendingUnmanagedWindowSnap.targetRect))",
        "unmanagedSnap.apply window=\(pendingUnmanagedWindowSnap.windowId) workspace=\(pendingUnmanagedWindowSnap.workspaceName) action=\(pendingUnmanagedWindowSnap.action.rawValue) target=\(debugDescribe(pendingUnmanagedWindowSnap.targetRect))"
    )
    window.lastFloatingSize = pendingUnmanagedWindowSnap.targetRect.size
    window.lastKnownActualRect = pendingUnmanagedWindowSnap.targetRect
    window.setAxFrame(pendingUnmanagedWindowSnap.targetRect.topLeftCorner, pendingUnmanagedWindowSnap.targetRect.size)
    return true
}
