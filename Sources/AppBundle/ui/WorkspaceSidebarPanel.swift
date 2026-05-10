import AppKit
import Common
import SwiftUI

let workspaceSidebarPanelId = "WinMux.workspaceSidebar"
let workspaceSidebarContentLeadingInset: CGFloat = 8
let workspaceSidebarContentTrailingInset: CGFloat = 8
let workspaceSidebarCompactRailHorizontalInset: CGFloat = 4
let workspaceSidebarSectionInnerHorizontalInset: CGFloat = 4
let workspaceSidebarBadgeWidth: CGFloat = 18
let workspaceSidebarHeaderSpacing: CGFloat = 10
let workspaceSidebarRowsRevealProgress: CGFloat = 0.58
let workspaceSidebarSectionCornerRadius: CGFloat = 10
let workspaceSidebarRowCornerRadius: CGFloat = 6
let workspaceSidebarRowHorizontalPadding: CGFloat = 7
let workspaceSidebarHeaderLeadingPadding: CGFloat = 3
let workspaceSidebarWindowRowsLeadingIndent: CGFloat = 4
let workspaceSidebarPagerHeight: CGFloat = 32
let workspaceSidebarActiveWorkspaceTint = Color(nsColor: .systemBlue)
let workspaceSidebarHoverAnimation: Animation = .interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.06)
let workspaceSidebarReducedMotionHoverAnimation: Animation = .easeOut(duration: 0.14)
let workspaceSidebarProjectSwipeIntentThreshold: CGFloat = 5
let workspaceSidebarProjectSwipeNavigateThreshold: CGFloat = 44
let workspaceSidebarProjectSwipeCreateThreshold: CGFloat = 104
let workspaceSidebarProjectSwipeFormationStart: CGFloat = 22
let workspaceSidebarHoverOpenThresholdFraction: CGFloat = 0.75
let workspaceSidebarDisplayEdgeCompactionMargin: CGFloat = 12
@MainActor
var workspaceSidebarDropTargets: [WorkspaceSidebarDropTarget] = []

struct WorkspaceSidebarProjectColorPreset: Hashable, Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
}

let workspaceSidebarProjectColorPresets: [WorkspaceSidebarProjectColorPreset] = [
    WorkspaceSidebarProjectColorPreset(name: "Blue", hex: "#60A5FA"),
    WorkspaceSidebarProjectColorPreset(name: "Cyan", hex: "#22D3EE"),
    WorkspaceSidebarProjectColorPreset(name: "Green", hex: "#34D399"),
    WorkspaceSidebarProjectColorPreset(name: "Yellow", hex: "#FBBF24"),
    WorkspaceSidebarProjectColorPreset(name: "Orange", hex: "#FB923C"),
    WorkspaceSidebarProjectColorPreset(name: "Red", hex: "#F87171"),
    WorkspaceSidebarProjectColorPreset(name: "Pink", hex: "#F472B6"),
    WorkspaceSidebarProjectColorPreset(name: "Violet", hex: "#A78BFA"),
]

@MainActor
func workspaceSidebarCompactSectionWidth() -> CGFloat {
    max(
        CGFloat(config.workspaceSidebar.collapsedWidth) - (workspaceSidebarCompactRailHorizontalInset * 2),
        workspaceSidebarBadgeWidth + (workspaceSidebarSectionInnerHorizontalInset * 2),
    )
}

@MainActor
func workspaceSidebarExpandedSectionWidth() -> CGFloat {
    max(
        CGFloat(config.workspaceSidebar.width) -
            workspaceSidebarContentLeadingInset -
            workspaceSidebarContentTrailingInset,
        workspaceSidebarCompactSectionWidth(),
    )
}

@MainActor
func workspaceSidebarSectionWidth(_ expansionProgress: CGFloat) -> CGFloat {
    let compact = workspaceSidebarCompactSectionWidth()
    let expanded = workspaceSidebarExpandedSectionWidth()
    return compact + (expanded - compact) * expansionProgress
}

func workspaceSidebarOuterLeadingPadding(isCompact: Bool) -> CGFloat {
    isCompact ? workspaceSidebarCompactRailHorizontalInset : workspaceSidebarContentLeadingInset
}

func workspaceSidebarOuterTrailingPadding(isCompact: Bool) -> CGFloat {
    isCompact ? workspaceSidebarCompactRailHorizontalInset : workspaceSidebarContentTrailingInset
}

func workspaceSidebarStatusBottomPadding(isCompact: Bool) -> CGFloat {
    workspaceSidebarOuterLeadingPadding(isCompact: isCompact)
}

@MainActor
func workspaceSidebarContentWidth(_ expansionProgress: CGFloat) -> CGFloat {
    max(
        workspaceSidebarSectionWidth(expansionProgress) -
            (workspaceSidebarSectionInnerHorizontalInset * 2) -
            workspaceSidebarBadgeWidth -
            workspaceSidebarHeaderSpacing,
        0,
    )
}

func workspaceSidebarVisibleWorkspacesByProject(
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
    selectedScopeId: String,
    focusedMonitorScopeId: String,
) -> [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]] {
    var result: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]] = [:]
    for workspace in workspaces where workspaceSidebarWorkspaceMatchesScope(
        workspaceMonitorScopeId: workspace.monitorScopeId,
        selectedScopeId: selectedScopeId,
        focusedMonitorScopeId: focusedMonitorScopeId,
    ) {
        result[workspace.projectId, default: []].append(workspace)
    }
    return result
}

func shouldRenderWorkspaceSidebarProjectPage(
    index: Int,
    displayIndex: Int,
    swipeDirection: Int?,
    projectCount: Int,
) -> Bool {
    guard index != displayIndex else { return true }
    guard let swipeDirection,
          let targetIndex = workspaceSidebarProjectIndexAfterSwipe(
            currentIndex: displayIndex,
            projectCount: projectCount,
            direction: swipeDirection,
          )
    else {
        return false
    }
    return index == targetIndex
}

enum WorkspaceSidebarDropTargetKind: Equatable {
    case workspace(String)
    case newWorkspace
    case monitor(String)
}

struct WorkspaceSidebarDropTarget {
    let kind: WorkspaceSidebarDropTargetKind
    let rect: Rect
}

struct WorkspaceSidebarDropTargetFrame: Equatable {
    let kind: WorkspaceSidebarDropTargetKind
    let frame: CGRect
}

struct WorkspaceSidebarDropTargetPreferenceKey: PreferenceKey {
    static let defaultValue: [WorkspaceSidebarDropTargetFrame] = []

    static func reduce(value: inout [WorkspaceSidebarDropTargetFrame], nextValue: () -> [WorkspaceSidebarDropTargetFrame]) {
        value.append(contentsOf: nextValue())
    }
}

@MainActor
func workspaceSidebarDropTarget(at mouseLocation: CGPoint) -> WorkspaceSidebarDropTarget? {
    workspaceSidebarDropTargets.last(where: { $0.rect.contains(mouseLocation) })
}

func shouldLockWorkspaceSidebarExpansion(
    hasDropPreview: Bool,
    hasPinnedDraggedWindow: Bool,
    isSidebarDragInProgress: Bool,
    hasActiveEditor: Bool,
) -> Bool {
    hasDropPreview || hasPinnedDraggedWindow || isSidebarDragInProgress || hasActiveEditor
}

func isWorkspaceSidebarDragInProgress(kind: MouseManipulationKind, startedInSidebar: Bool) -> Bool {
    kind == .move && startedInSidebar
}

@MainActor
func isWorkspaceSidebarDragInProgress() -> Bool {
    isWorkspaceSidebarDragInProgress(
        kind: getCurrentMouseManipulationKind(),
        startedInSidebar: getCurrentMouseDragStartedInSidebar(),
    )
}

func shouldHandleWorkspaceSidebarActivation(isEditing: Bool, isSidebarDragInProgress: Bool) -> Bool {
    !isEditing && !isSidebarDragInProgress
}

func shouldHandleWorkspaceSidebarActivation(
    editingWorkspaceName: String?,
    isSidebarDragInProgress: Bool,
) -> Bool {
    shouldHandleWorkspaceSidebarActivation(
        isEditing: editingWorkspaceName != nil,
        isSidebarDragInProgress: isSidebarDragInProgress,
    )
}

func workspaceSidebarProjectSwipeDirection(
    horizontalTranslation: CGFloat,
    verticalTranslation: CGFloat,
    minimumDistance: CGFloat = workspaceSidebarProjectSwipeIntentThreshold,
) -> Int? {
    let horizontalDistance = abs(horizontalTranslation)
    guard horizontalDistance >= minimumDistance,
          horizontalDistance > abs(verticalTranslation) * 1.8
    else {
        return nil
    }
    return horizontalTranslation < 0 ? 1 : -1
}

func workspaceSidebarProjectIndexAfterSwipe(
    currentIndex: Int?,
    projectCount: Int,
    direction: Int,
) -> Int? {
    guard let currentIndex,
          projectCount > 0,
          (0 ..< projectCount).contains(currentIndex)
    else {
        return nil
    }
    let nextIndex = currentIndex + direction
    return (0 ..< projectCount).contains(nextIndex) ? nextIndex : nil
}

func shouldCreateWorkspaceSidebarProjectAfterSwipe(
    currentIndex: Int?,
    projectCount: Int,
    direction: Int,
    distance: CGFloat,
) -> Bool {
    guard let currentIndex,
          projectCount > 0
    else {
        return false
    }
    let pulledBeforeFirst = direction < 0 && currentIndex == 0
    let pulledAfterLast = direction > 0 && currentIndex == projectCount - 1
    return (pulledBeforeFirst || pulledAfterLast) && distance >= workspaceSidebarProjectSwipeCreateThreshold
}

func workspaceSidebarProjectEdgeCreationProgress(
    currentIndex: Int?,
    projectCount: Int,
    direction: Int?,
    distance: CGFloat,
) -> CGFloat {
    guard let currentIndex,
          let direction,
          projectCount > 0
    else {
        return 0
    }
    let pulledBeforeFirst = direction < 0 && currentIndex == 0
    let pulledAfterLast = direction > 0 && currentIndex == projectCount - 1
    guard pulledBeforeFirst || pulledAfterLast else { return 0 }
    let range = max(workspaceSidebarProjectSwipeCreateThreshold - workspaceSidebarProjectSwipeFormationStart, 1)
    return min(max((distance - workspaceSidebarProjectSwipeFormationStart) / range, 0), 1)
}

func workspaceSidebarProjectResistedOffset(
    horizontalTranslation: CGFloat,
    currentIndex: Int?,
    projectCount: Int,
) -> CGFloat {
    let direction = horizontalTranslation < 0 ? 1 : -1
    let isPastProjectEdge = workspaceSidebarProjectIndexAfterSwipe(
        currentIndex: currentIndex,
        projectCount: projectCount,
        direction: direction,
    ) == nil
    let divisor: CGFloat = isPastProjectEdge ? 2.2 : 1.0
    let limit: CGFloat = isPastProjectEdge ? 52 : 72
    return max(-limit, min(limit, horizontalTranslation / divisor))
}

func workspaceSidebarProjectPagerDragOffset(
    horizontalTranslation: CGFloat,
    currentIndex: Int?,
    projectCount: Int,
    pageWidth: CGFloat,
) -> CGFloat {
    guard pageWidth > 0,
          let direction = workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: 0,
            minimumDistance: 1,
          )
    else {
        return 0
    }
    guard workspaceSidebarProjectIndexAfterSwipe(
        currentIndex: currentIndex,
        projectCount: projectCount,
        direction: direction,
    ) != nil else {
        return workspaceSidebarProjectResistedOffset(
            horizontalTranslation: horizontalTranslation,
            currentIndex: currentIndex,
            projectCount: projectCount,
        )
    }
    return max(-pageWidth, min(pageWidth, horizontalTranslation))
}

func workspaceSidebarProjectSwipeSwitchProgress(distance: CGFloat) -> CGFloat {
    min(max(distance / workspaceSidebarProjectSwipeNavigateThreshold, 0), 1)
}

func workspaceSidebarProjectSwipeTranslationAfterScroll(
    currentTranslation: CGFloat,
    scrollingDeltaX: CGFloat,
) -> CGFloat {
    currentTranslation - scrollingDeltaX
}

func workspaceSidebarProjectHue(projectId: WorkspaceProjectId) -> Double {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in projectId.rawValue.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return Double(hash % 360) / 360.0
}

func workspaceSidebarProjectColor(projectId: WorkspaceProjectId) -> Color {
    workspaceSidebarProjectColor(projectId: projectId, configuredHex: nil)
}

func workspaceSidebarProjectColor(projectId: WorkspaceProjectId, configuredHex: String?) -> Color {
    if let configuredHex,
       let color = workspaceSidebarColor(hex: configuredHex) {
        return color
    }
    return Color(
        hue: workspaceSidebarProjectHue(projectId: projectId),
        saturation: 0.72,
        brightness: 0.92,
    )
}

func workspaceSidebarColor(hex: String) -> Color? {
    guard let nsColor = workspaceSidebarNSColor(hex: hex) else { return nil }
    return Color(nsColor: nsColor)
}

func workspaceSidebarNSColor(hex: String) -> NSColor? {
    guard let normalized = normalizedWorkspaceSidebarColorHex(hex),
          let rgb = UInt32(String(normalized.dropFirst()), radix: 16)
    else {
        return nil
    }
    return NSColor(
        srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
        green: CGFloat((rgb >> 8) & 0xff) / 255,
        blue: CGFloat(rgb & 0xff) / 255,
        alpha: 1,
    )
}

func workspaceSidebarProjectColorSwatchImage(hex: String, isSelected: Bool) -> NSImage {
    let color = workspaceSidebarNSColor(hex: hex) ?? NSColor.white.withAlphaComponent(0.65)
    return workspaceSidebarSwatchImage {
        drawWorkspaceSidebarSwatchCircle(
            fill: color,
            stroke: NSColor.white.withAlphaComponent(isSelected ? 0.92 : 0.26),
            lineWidth: isSelected ? 1.5 : 1,
        )
        guard isSelected else { return }
        let checkPath = NSBezierPath()
        checkPath.move(to: NSPoint(x: 5.2, y: 8.0))
        checkPath.line(to: NSPoint(x: 7.2, y: 6.0))
        checkPath.line(to: NSPoint(x: 10.9, y: 10.2))
        checkPath.lineCapStyle = .round
        checkPath.lineJoinStyle = .round
        checkPath.lineWidth = 1.5
        NSColor.white.setStroke()
        checkPath.stroke()
    }
}

func workspaceSidebarAutomaticColorSwatchImage(isSelected: Bool) -> NSImage {
    workspaceSidebarSwatchImage {
        drawWorkspaceSidebarSwatchCircle(
            fill: NSColor.white.withAlphaComponent(isSelected ? 0.20 : 0.10),
            stroke: NSColor.white.withAlphaComponent(isSelected ? 0.75 : 0.35),
            lineWidth: isSelected ? 1.4 : 1,
        )

        let slashPath = NSBezierPath()
        slashPath.move(to: NSPoint(x: 4.3, y: 4.4))
        slashPath.line(to: NSPoint(x: 11.7, y: 11.6))
        slashPath.lineCapStyle = .round
        slashPath.lineWidth = 1.2
        NSColor.white.withAlphaComponent(0.72).setStroke()
        slashPath.stroke()
    }
}

func workspaceSidebarSwatchImage(draw: () -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: 16, height: 16))
    image.lockFocus()
    draw()
    image.unlockFocus()
    image.isTemplate = false
    return image
}

func drawWorkspaceSidebarSwatchCircle(fill: NSColor, stroke: NSColor, lineWidth: CGFloat) {
    let circlePath = NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 10, height: 10))
    fill.setFill()
    circlePath.fill()
    stroke.setStroke()
    circlePath.lineWidth = lineWidth
    circlePath.stroke()
}

func nextWorkspaceSidebarHoveredWorkspaceName(
    currentHoveredWorkspaceName: String?,
    workspaceName: String,
    isHovering: Bool,
) -> String? {
    if isHovering {
        return workspaceName
    }
    return currentHoveredWorkspaceName == workspaceName ? nil : currentHoveredWorkspaceName
}

func nextWorkspaceSidebarHoveredWindowId(
    currentHoveredWindowId: UInt32?,
    windowId: UInt32,
    isHovering: Bool,
) -> UInt32? {
    if isHovering {
        return windowId
    }
    return currentHoveredWindowId == windowId ? nil : currentHoveredWindowId
}

func workspaceSidebarHoverCueWidth(collapsedWidth: CGFloat, expandedWidth: CGFloat) -> CGFloat {
    min(collapsedWidth, expandedWidth)
}

func isWorkspaceSidebarHoverDeepEnoughToExpand(
    mouseX: CGFloat,
    sidebarMinX: CGFloat,
    collapsedWidth: CGFloat,
) -> Bool {
    guard collapsedWidth > 0 else { return false }
    let sidebarMaxX = sidebarMinX + collapsedWidth
    return sidebarMaxX - mouseX >= collapsedWidth * workspaceSidebarHoverOpenThresholdFraction
}

func isMouseWindowDragInProgress(kind: MouseManipulationKind, draggedWindowId: UInt32?, isLeftMouseButtonDown: Bool) -> Bool {
    kind == .move && draggedWindowId != nil && isLeftMouseButtonDown
}

@MainActor
func isMouseWindowDragInProgress() -> Bool {
    isMouseWindowDragInProgress(
        kind: getCurrentMouseManipulationKind(),
        draggedWindowId: currentlyManipulatedWithMouseWindowId,
        isLeftMouseButtonDown: isLeftMouseButtonDown,
    )
}

func shouldDelayWorkspaceSidebarExpansion(
    isExpanded: Bool,
    isExpansionLocked: Bool,
    isMouseWindowDragInProgress: Bool,
) -> Bool {
    !isExpanded && !isExpansionLocked && !isMouseWindowDragInProgress
}

@MainActor
func isMousePushedAgainstDisplayEdge() -> Bool {
    let mouseLocation = NSEvent.mouseLocation
    let screenFrame = NSScreen.screens
        .first(where: { $0.frame.contains(mouseLocation) })?
        .frame ?? NSScreen.main?.frame

    guard let screenFrame else { return false }
    return
        mouseLocation.x <= screenFrame.minX + workspaceSidebarDisplayEdgeCompactionMargin ||
        mouseLocation.x >= screenFrame.maxX - workspaceSidebarDisplayEdgeCompactionMargin ||
        mouseLocation.y <= screenFrame.minY + workspaceSidebarDisplayEdgeCompactionMargin ||
        mouseLocation.y >= screenFrame.maxY - workspaceSidebarDisplayEdgeCompactionMargin
}
