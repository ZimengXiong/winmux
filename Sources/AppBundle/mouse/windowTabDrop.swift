import AppKit
import Common

let windowDropPreviewInset: CGFloat = 0
let windowTabInsertPreviewExtraHeight: CGFloat = 18
let windowTabInsertPreviewMinHeight: CGFloat = 52
let windowTabInsertInteractionHorizontalInset: CGFloat = 24
let windowTabInsertInteractionTopInset: CGFloat = 12
let windowTabInsertInteractionBottomInset: CGFloat = 32
let windowTabInsertStickyTrackingHorizontalInset: CGFloat = 24
let windowTabInsertStickyTrackingTopInset: CGFloat = 20
let windowTabInsertStickyTrackingBottomInset: CGFloat = 36

@MainActor
var pendingWindowDragIntent: PendingWindowDragIntent? = nil
@MainActor
var windowDragActualRectRefreshTask: Task<Void, Never>? = nil
@MainActor
var windowDragActualRectCache: [UInt32: Rect] = [:]
@MainActor
var lastWindowDragHitTestLogSignature: String? = nil
@MainActor
var lastWindowDragIntentLogSignature: String? = nil

struct PendingWindowDragIntent {
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
    let isPointerSettled: Bool
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

struct WindowDragIntentDestination {
    let kind: WindowDragIntentKind
    let previewContainerRect: Rect
    let previewRect: Rect
    let interactionRect: Rect
    let title: String
    let subtitle: String
    let previewStyle: WindowTabDropPreviewStyle
    let previewGeometry: WindowTabDropPreviewGeometry
    let isGroup: Bool
    let previewZones: [WindowDragIntentPreviewZone]

    init(
        kind: WindowDragIntentKind,
        previewContainerRect: Rect,
        previewRect: Rect,
        interactionRect: Rect,
        title: String,
        subtitle: String,
        previewStyle: WindowTabDropPreviewStyle,
        previewGeometry: WindowTabDropPreviewGeometry,
        isGroup: Bool,
        previewZones: [WindowDragIntentPreviewZone] = [],
    ) {
        self.kind = kind
        self.previewContainerRect = previewContainerRect
        self.previewRect = previewRect
        self.interactionRect = interactionRect
        self.title = title
        self.subtitle = subtitle
        self.previewStyle = previewStyle
        self.previewGeometry = previewGeometry
        self.isGroup = isGroup
        self.previewZones = previewZones
    }

    @MainActor
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
            isPointerSettled: WindowDragFrameGate.shared.state(for: sourceWindowId)?.isSettled ?? false,
            zones: previewZones.map(\.viewModel),
        )
    }

    func previewReferenceWindowId(sourceWindowId: UInt32) -> UInt32? {
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

struct WindowDragIntentPreviewZone {
    let rect: Rect
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let isActive: Bool

    var viewModel: WindowTabDropPreviewZoneViewModel {
        WindowTabDropPreviewZoneViewModel(
            frame: rect.toAppKitScreenRect,
            style: style,
            geometry: geometry,
            isActive: isActive,
        )
    }
}

extension WindowDragIntentDestination {
    func withPreviewZones(_ zones: [WindowDragIntentPreviewZone]) -> WindowDragIntentDestination {
        WindowDragIntentDestination(
            kind: kind,
            previewContainerRect: previewContainerRect,
            previewRect: previewRect,
            interactionRect: interactionRect,
            title: title,
            subtitle: subtitle,
            previewStyle: previewStyle,
            previewGeometry: previewGeometry,
            isGroup: isGroup,
            previewZones: zones,
        )
    }
}

struct WindowStackSplitPreview {
    let rect: Rect
    let geometry: WindowTabDropPreviewGeometry
}

func debugDescribe(_ rect: Rect?) -> String {
    guard let rect else { return "nil" }
    return "(\(rect.topLeftX), \(rect.topLeftY), \(rect.width), \(rect.height))"
}

func debugDescribe(_ point: CGPoint) -> String {
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
func currentWindowDragActualRect(_ window: Window) -> Rect? {
    guard let current = window.lastKnownActualRect else { return windowDragActualRectCache[window.windowId] }
    return resolveWindowDragActualRect(
        cached: windowDragActualRectCache[window.windowId],
        candidate: current,
        layout: window.lastAppliedLayoutPhysicalRect,
    )
}

func debugDescribe(_ subject: WindowDragSubject) -> String {
    switch subject {
        case .window: "window"
        case .group: "group"
    }
}

func debugDescribe(_ kind: WindowDragIntentKind) -> String {
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

func debugDescribe(_ intent: WindowBodyDragIntent?) -> String {
    guard let intent else { return "nil" }
    switch intent {
        case .swap:
            return "swap"
        case .stackSplit(let position):
            return "stackSplit(\(position))"
    }
}

@MainActor
func debugDescribe(_ window: Window?) -> String {
    guard let window else { return "nil" }
    return "w:\(window.windowId) actual=\(debugDescribe(window.lastKnownActualRect)) layout=\(debugDescribe(window.lastAppliedLayoutPhysicalRect)) visible=\(debugDescribe(window.windowDragVisibleRect)) moveVisible=\(debugDescribe(window.moveNode.windowDragVisibleRect))"
}

@MainActor
func debugDescribe(_ node: TreeNode) -> String {
    switch node.tilingTreeNodeCasesOrDie() {
        case .window(let window):
            return "window[\(window.windowId)] visible=\(debugDescribe(node.windowDragVisibleRect))"
        case .tilingContainer(let container):
            return "container[\(ObjectIdentifier(container).hashValue)] layout=\(container.layout) visible=\(debugDescribe(node.windowDragVisibleRect))"
    }
}

@MainActor
func logWindowDragHitTestIfNeeded(signature: String, _ message: @autoclosure () -> String) {
    guard lastWindowDragHitTestLogSignature != signature else { return }
    lastWindowDragHitTestLogSignature = signature
    debugFocusLog(message())
}

@MainActor
func logWindowDragIntentIfNeeded(signature: String, _ message: @autoclosure () -> String) {
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
            mouseLocation: MousePointerTracker.shared.currentSample.point,
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
func workspaceSidebarCursorPreviewRect(at mouseLocation: CGPoint) -> Rect {
    workspaceSidebarCursorPreviewRect(at: mouseLocation, sidebarRect: WorkspaceSidebarPanel.shared.visibleScreenRectNormalized())
}

func workspaceSidebarCursorPreviewRect(at mouseLocation: CGPoint, sidebarRect: Rect?) -> Rect {
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
