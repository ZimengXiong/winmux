import AppKit
import Common
import SwiftUI

private let workspaceSidebarPanelId = "WinMux.workspaceSidebar"
private let workspaceSidebarContentLeadingInset: CGFloat = 8
private let workspaceSidebarContentTrailingInset: CGFloat = 8
private let workspaceSidebarCompactRailHorizontalInset: CGFloat = 4
private let workspaceSidebarSectionInnerHorizontalInset: CGFloat = 4
private let workspaceSidebarBadgeWidth: CGFloat = 18
private let workspaceSidebarHeaderSpacing: CGFloat = 10
private let workspaceSidebarRowsRevealProgress: CGFloat = 0.58
private let workspaceSidebarSectionCornerRadius: CGFloat = 10
private let workspaceSidebarRowCornerRadius: CGFloat = 6
private let workspaceSidebarRowHorizontalPadding: CGFloat = 7
private let workspaceSidebarHeaderLeadingPadding: CGFloat = 3
private let workspaceSidebarWindowRowsLeadingIndent: CGFloat = 4
private let workspaceSidebarPagerHeight: CGFloat = 32
private let workspaceSidebarActiveWorkspaceTint = Color(nsColor: .systemBlue)
private let workspaceSidebarHoverAnimation: Animation = .interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.06)
private let workspaceSidebarReducedMotionHoverAnimation: Animation = .easeOut(duration: 0.14)
private let workspaceSidebarProjectSwipeIntentThreshold: CGFloat = 5
private let workspaceSidebarProjectSwipeNavigateThreshold: CGFloat = 44
private let workspaceSidebarProjectSwipeCreateThreshold: CGFloat = 104
private let workspaceSidebarProjectSwipeFormationStart: CGFloat = 22
private let workspaceSidebarHoverOpenThresholdFraction: CGFloat = 0.75
private let workspaceSidebarDisplayEdgeCompactionMargin: CGFloat = 12
@MainActor
private var workspaceSidebarDropTargets: [WorkspaceSidebarDropTarget] = []

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
private func workspaceSidebarCompactSectionWidth() -> CGFloat {
    max(
        CGFloat(config.workspaceSidebar.collapsedWidth) - (workspaceSidebarCompactRailHorizontalInset * 2),
        workspaceSidebarBadgeWidth + (workspaceSidebarSectionInnerHorizontalInset * 2),
    )
}

@MainActor
private func workspaceSidebarExpandedSectionWidth() -> CGFloat {
    max(
        CGFloat(config.workspaceSidebar.width) -
            workspaceSidebarContentLeadingInset -
            workspaceSidebarContentTrailingInset,
        workspaceSidebarCompactSectionWidth(),
    )
}

@MainActor
private func workspaceSidebarSectionWidth(_ expansionProgress: CGFloat) -> CGFloat {
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
private func workspaceSidebarContentWidth(_ expansionProgress: CGFloat) -> CGFloat {
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

private func workspaceSidebarSwatchImage(draw: () -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: 16, height: 16))
    image.lockFocus()
    draw()
    image.unlockFocus()
    image.isTemplate = false
    return image
}

private func drawWorkspaceSidebarSwatchCircle(fill: NSColor, stroke: NSColor, lineWidth: CGFloat) {
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
private func isMousePushedAgainstDisplayEdge() -> Bool {
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

@MainActor
final class WorkspaceSidebarPanel: NSPanelHud {
    static let shared = WorkspaceSidebarPanel()

    private let hostingView = NSHostingView(rootView: WorkspaceSidebarView(viewModel: TrayMenuModel.shared))
    private var pendingExpand: DispatchWorkItem?
    private var pendingCollapse: DispatchWorkItem?
    private var pendingCollapseFinalize: DispatchWorkItem?
    private var isHoverMonitoring = false
    private var lastHoverMonitorTimestamp: CFTimeInterval = 0
    private var menuTrackingDepth = 0
    private var inlineTextEditingActive = false
    private var menuTrackingObservers: [NSObjectProtocol] = []
    private let hoverExitTolerance: CGFloat = 20
    private let hoverPollInterval: TimeInterval = 1.0 / 30.0
    private let hoverOpenDelay: TimeInterval = 0.05
    private let hoverCueAnimationResponse: TimeInterval = 0.18
    private let animationDuration: TimeInterval = 0.14

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(workspaceSidebarPanelId)
        styleMask.remove(.nonactivatingPanel)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        applyWinMuxLayer(.workspaceSidebar)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        installMenuTrackingObservers()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func beginInlineTextEditing() {
        inlineTextEditingActive = true
        prepareForInlineTextEditing()
    }

    func endInlineTextEditing() {
        guard inlineTextEditingActive else { return }
        inlineTextEditingActive = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.updateHoverStateFromMousePosition()
        }
    }

    func prepareForInlineTextEditing() {
        pendingExpand?.cancel()
        pendingExpand = nil
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
        expandSidebar(to: CGFloat(config.workspaceSidebar.width))
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        guard TrayMenuModel.shared.isEnabled,
              config.workspaceSidebar.enabled,
              let screen = NSScreen.screens.getOrNil(atIndex: workspaceSidebarResolvedPanelMonitor().monitorAppKitNsScreenScreensId - 1) ?? NSScreen.screens.first
        else {
            stopHoverMonitoring()
            resetHiddenSidebarState()
            return
        }

        let sidebarConfig = config.workspaceSidebar
        let expandedWidth = CGFloat(sidebarConfig.width)
        let collapsedWidth = CGFloat(sidebarConfig.collapsedWidth)
        guard expandedWidth > 0, collapsedWidth > 0 else {
            resetHiddenSidebarState()
            return
        }

        let screenFrame = screen.frame
        let menuBarReserveHeight = min(
            CGFloat(sidebarConfig.menuBarReserveHeight),
            max(screenFrame.height - 1, 0),
        )
        let frame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: expandedWidth,
            height: screenFrame.height - menuBarReserveHeight,
        )

        if self.frame != frame {
            workspaceSidebarDropTargets = []
            setFrame(frame, display: true, animate: false)
        }
        if TrayMenuModel.shared.workspaceSidebarVisibleWidth == 0 {
            TrayMenuModel.shared.workspaceSidebarVisibleWidth = TrayMenuModel.shared.isWorkspaceSidebarExpanded
                ? expandedWidth
                : collapsedWidth
        }
        updateMousePassthrough()
        startHoverMonitoring()
        orderFrontRegardless()
    }

    func refreshForCurrentDragIfNeeded() {
        guard isMouseWindowDragInProgress() else { return }
        let targetMonitor = mouseLocation.monitorApproximation
        let screen = NSScreen.screens.getOrNil(atIndex: targetMonitor.monitorAppKitNsScreenScreensId - 1) ?? NSScreen.screens.first
        guard let screen,
              frame.minX != screen.frame.minX || frame.minY != screen.frame.minY
        else { return }
        refresh()
    }

    func updateDropTargets(_ targets: [WorkspaceSidebarDropTargetFrame]) {
        workspaceSidebarDropTargets = targets.compactMap { target in
            let windowRect = hostingView.convert(target.frame, to: nil)
            let screenRect = convertToScreen(windowRect)
            return WorkspaceSidebarDropTarget(kind: target.kind, rect: screenRect.monitorFrameNormalized())
        }
    }

    func visibleScreenRectNormalized() -> Rect? {
        guard isVisible, TrayMenuModel.shared.workspaceSidebarVisibleWidth > 0 else { return nil }
        return CGRect(
            x: frame.minX,
            y: frame.minY,
            width: min(TrayMenuModel.shared.workspaceSidebarVisibleWidth, frame.width),
            height: frame.height,
        ).monitorFrameNormalized()
    }

    private func startHoverMonitoring() {
        guard !isHoverMonitoring else { return }
        isHoverMonitoring = true
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] timestamp in
            guard let self else { return }
            guard timestamp - self.lastHoverMonitorTimestamp >= self.hoverPollInterval else { return }
            self.lastHoverMonitorTimestamp = timestamp
            self.updateHoverStateFromMousePosition()
        }
    }

    private func stopHoverMonitoring() {
        pendingExpand?.cancel()
        pendingExpand = nil
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
        isHoverMonitoring = false
        lastHoverMonitorTimestamp = 0
        DisplayRefreshDriver.shared.remove(owner: self)
    }

    private func resetHiddenSidebarState() {
        workspaceSidebarDropTargets = []
        TrayMenuModel.shared.workspaceSidebarDropPreview = nil
        TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = nil
        TrayMenuModel.shared.workspaceSidebarVisibleWidth = 0
        orderOut(nil)
    }

    private func updateHoverStateFromMousePosition() {
        updateMousePassthrough()
        setHovering(isMouseInsideHoverRegion())
    }

    private func shouldLockExpansionForSidebarDrag() -> Bool {
        shouldLockWorkspaceSidebarExpansion(
            hasDropPreview: TrayMenuModel.shared.workspaceSidebarDropPreview != nil,
            hasPinnedDraggedWindow: hasPinnedDraggedWindow(),
            isSidebarDragInProgress: getCurrentMouseManipulationKind() == .move && getCurrentMouseDragStartedInSidebar(),
            hasActiveEditor: menuTrackingDepth > 0 || inlineTextEditingActive,
        ) || isMouseWindowDragInProgress()
    }

    private func installMenuTrackingObservers() {
        let center = NotificationCenter.default
        menuTrackingObservers = [
            center.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.beginMenuTrackingIfNeeded()
                }
            },
            center.addObserver(
                forName: NSMenu.didEndTrackingNotification,
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.endMenuTrackingIfNeeded()
                }
            },
        ]
    }

    private func beginMenuTrackingIfNeeded() {
        guard isVisible,
              TrayMenuModel.shared.workspaceSidebarVisibleWidth > 0,
              isMouseInsideHoverRegion()
        else {
            return
        }
        menuTrackingDepth += 1
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
        expandSidebar(to: CGFloat(config.workspaceSidebar.width))
    }

    private func endMenuTrackingIfNeeded() {
        guard menuTrackingDepth > 0 else { return }
        menuTrackingDepth -= 1
        guard menuTrackingDepth == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.updateHoverStateFromMousePosition()
        }
    }

    private func animateVisibleSidebarWidth(_ width: CGFloat, animation: Animation) {
        withAnimation(animation) {
            TrayMenuModel.shared.workspaceSidebarVisibleWidth = width
        }
        updateMousePassthrough()
    }

    private func expandSidebar(to expandedWidth: CGFloat) {
        pendingExpand?.cancel()
        pendingExpand = nil
        TrayMenuModel.shared.isWorkspaceSidebarExpanded = true
        if !isVisible {
            refresh()
        }
        guard TrayMenuModel.shared.workspaceSidebarVisibleWidth != expandedWidth else {
            updateMousePassthrough()
            return
        }
        animateVisibleSidebarWidth(expandedWidth, animation: .easeInOut(duration: animationDuration))
    }

    private func setHovering(_ isHovering: Bool) {
        let sidebarConfig = config.workspaceSidebar
        let expandedWidth = CGFloat(sidebarConfig.width)
        let collapsedWidth = CGFloat(sidebarConfig.collapsedWidth)
        let cueWidth = workspaceSidebarHoverCueWidth(
            collapsedWidth: collapsedWidth,
            expandedWidth: expandedWidth,
        )

        if isHovering {
            let isExpansionLocked = shouldLockExpansionForSidebarDrag()
            let isExternalWindowDrag = isMouseWindowDragInProgress()
            let isSidebarOriginatedDrag = getCurrentMouseDragStartedInSidebar()
            pendingCollapse?.cancel()
            pendingCollapse = nil
            pendingCollapseFinalize?.cancel()
            pendingCollapseFinalize = nil

            if isExternalWindowDrag && !isSidebarOriginatedDrag && isMousePushedAgainstDisplayEdge() {
                pendingExpand?.cancel()
                pendingExpand = nil
                if !isVisible {
                    refresh()
                }
                if TrayMenuModel.shared.workspaceSidebarVisibleWidth != collapsedWidth {
                    animateVisibleSidebarWidth(
                        collapsedWidth,
                        animation: .easeInOut(duration: animationDuration),
                    )
                } else {
                    updateMousePassthrough()
                }
                return
            }

            if !shouldDelayWorkspaceSidebarExpansion(
                isExpanded: TrayMenuModel.shared.isWorkspaceSidebarExpanded,
                isExpansionLocked: isExpansionLocked,
                isMouseWindowDragInProgress: isExternalWindowDrag,
            ) {
                expandSidebar(to: expandedWidth)
                return
            }

            if !isVisible {
                refresh()
            }
            if TrayMenuModel.shared.workspaceSidebarVisibleWidth < cueWidth {
                animateVisibleSidebarWidth(
                    cueWidth,
                    animation: .spring(response: hoverCueAnimationResponse, dampingFraction: 0.72),
                )
            } else {
                updateMousePassthrough()
            }

            guard isMouseDeepEnoughToExpand(collapsedWidth: collapsedWidth) else {
                pendingExpand?.cancel()
                pendingExpand = nil
                return
            }

            guard pendingExpand == nil else { return }
            let expand = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingExpand = nil
                guard self.isMouseInsideHoverRegion(),
                      self.isMouseDeepEnoughToExpand(collapsedWidth: collapsedWidth)
                else { return }
                self.expandSidebar(to: expandedWidth)
            }
            pendingExpand = expand
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverOpenDelay, execute: expand)
        } else {
            pendingExpand?.cancel()
            pendingExpand = nil
            if shouldLockExpansionForSidebarDrag() {
                return
            }
            let needsCollapse =
                TrayMenuModel.shared.isWorkspaceSidebarExpanded ||
                TrayMenuModel.shared.workspaceSidebarVisibleWidth != collapsedWidth
            if needsCollapse && pendingCollapse == nil {
                let collapse = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pendingCollapse = nil
                    if !self.isMouseInsideHoverRegion() && !self.shouldLockExpansionForSidebarDrag() {
                        self.animateVisibleSidebarWidth(
                            collapsedWidth,
                            animation: .easeInOut(duration: self.animationDuration),
                        )
                        let finalize = DispatchWorkItem { [weak self] in
                            guard let self else { return }
                            self.pendingCollapseFinalize = nil
                            guard !self.isMouseInsideHoverRegion() && !self.shouldLockExpansionForSidebarDrag() else { return }
                            TrayMenuModel.shared.isWorkspaceSidebarExpanded = false
                            self.updateMousePassthrough()
                        }
                        self.pendingCollapseFinalize = finalize
                        DispatchQueue.main.asyncAfter(deadline: .now() + self.animationDuration, execute: finalize)
                    }
                }
                pendingCollapse = collapse
                let collapseDelay: TimeInterval = TrayMenuModel.shared.isWorkspaceSidebarExpanded ? 0.08 : 0
                DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: collapse)
            }
        }
    }

    private func updateMousePassthrough() {
        let shouldIgnoreMouseEvents = !isMouseInsideVisibleRegion()
        if ignoresMouseEvents != shouldIgnoreMouseEvents {
            ignoresMouseEvents = shouldIgnoreMouseEvents
        }
    }

    private func isMouseInsideHoverRegion() -> Bool {
        guard isVisible else { return false }
        let mouseLocation = NSEvent.mouseLocation
        let sidebarConfig = config.workspaceSidebar
        let hoverWidth = max(
            TrayMenuModel.shared.workspaceSidebarVisibleWidth,
            CGFloat(sidebarConfig.collapsedWidth),
        ) + hoverExitTolerance
        let hoverRegion = NSRect(
            x: frame.minX,
            y: frame.minY,
            width: hoverWidth,
            height: frame.height,
        )
        return hoverRegion.contains(mouseLocation)
    }

    private func isMouseInsideVisibleRegion() -> Bool {
        guard isVisible else { return false }
        let mouseLocation = NSEvent.mouseLocation
        let visibleRegion = NSRect(
            x: frame.minX,
            y: frame.minY,
            width: TrayMenuModel.shared.workspaceSidebarVisibleWidth,
            height: frame.height,
        )
        return visibleRegion.contains(mouseLocation)
    }

    private func isMouseDeepEnoughToExpand(collapsedWidth: CGFloat) -> Bool {
        guard isVisible else { return false }
        return isWorkspaceSidebarHoverDeepEnoughToExpand(
            mouseX: NSEvent.mouseLocation.x,
            sidebarMinX: frame.minX,
            collapsedWidth: collapsedWidth,
        )
    }
}

@MainActor
private func focusWorkspaceFromSidebar(_ workspaceName: String) {
    runWorkspaceSidebarSession {
        _ = Workspace.existing(byName: workspaceName)?.focusWorkspace()
    }
}

@MainActor
private func runWorkspaceSidebarSession(_ body: @escaping @MainActor () async throws -> Void) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task { @MainActor in
        do {
            try await runLightSession(.menuBarButton, token) {
                try await body()
            }
        } catch {
            showWorkspaceSidebarError(error.localizedDescription)
        }
    }
}

@MainActor
private func showWorkspaceSidebarError(_ body: String) {
    MessageModel.shared.message = Message(
        description: "Workspace Sidebar Error",
        body: body,
    )
}

@MainActor
private func promptWorkspaceSidebarName(title: String, currentName: String) -> String? {
    let field = NSTextField(string: currentName)
    field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
    field.lineBreakMode = .byTruncatingTail

    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = "Enter a name."
    alert.accessoryView = field
    alert.addButton(withTitle: "Rename")
    alert.addButton(withTitle: "Cancel")

    let window = WorkspaceSidebarPanel.shared
    window.makeKey()
    field.becomeFirstResponder()
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
}

@MainActor
private func sidebarWorkspaceTargetMonitor(fallbackWindow: Window? = nil, fallbackPoint: CGPoint? = nil) -> Monitor {
    workspaceSidebarTargetMonitor(
        selectedMonitor: selectedWorkspaceSidebarMonitorScope(),
        fallbackPoint: fallbackPoint,
        fallbackWindowMonitor: fallbackWindow?.nodeMonitor,
        focusedMonitor: focus.workspace.workspaceMonitor,
    )
}

@MainActor
func workspaceSidebarTargetMonitor(
    selectedMonitor: Monitor?,
    fallbackPoint: CGPoint?,
    fallbackWindowMonitor: Monitor?,
    focusedMonitor: Monitor,
) -> Monitor {
    selectedMonitor ??
        fallbackPoint?.monitorApproximation ??
        fallbackWindowMonitor ??
        focusedMonitor
}

@MainActor
private func selectedWorkspaceSidebarMonitorScope() -> Monitor? {
    let selectedScopeId = TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId
    guard selectedScopeId != workspaceSidebarFocusedScopeId,
          selectedScopeId != workspaceSidebarAllScopeId
    else {
        return nil
    }
    return sortedMonitors.first { workspaceSidebarMonitorScopeId(for: $0) == selectedScopeId }
}

@MainActor
private func selectWorkspaceSidebarMonitorScope(_ scopeId: String) {
    guard TrayMenuModel.shared.workspaceSidebarMonitorScopes.contains(where: { $0.id == scopeId }) else { return }
    guard TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId != scopeId else { return }
    TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId = scopeId
    let visibleWorkspaceNames = Set(TrayMenuModel.shared.visibleWorkspaceSidebarWorkspaces.map(\.name))
    let sanitizedHoveredWorkspaceName = sanitizedWorkspaceSidebarHoveredWorkspaceName(
        visibleWorkspaceNames: visibleWorkspaceNames,
        hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
    )
    if TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName != sanitizedHoveredWorkspaceName {
        TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = sanitizedHoveredWorkspaceName
    }
}

@MainActor
private func createWorkspaceFromSidebarButton() {
    runWorkspaceSidebarSession {
        let targetMonitor = sidebarWorkspaceTargetMonitor()
        let projectId = sidebarWorkspaceTargetProjectId(targetMonitor: targetMonitor)
        let workspace = getOrCreateAdjacentBlankWorkspace(projectId: projectId, monitor: targetMonitor)
        _ = workspace.focusWorkspace()
    }
}

@MainActor
func createWorkspaceFromSidebarDrag(sourceNode: TreeNode, sourceWindow: Window) -> Bool {
    let targetMonitor = sidebarWorkspaceTargetMonitor(fallbackWindow: sourceWindow, fallbackPoint: mouseLocation)
    let projectId = sidebarWorkspaceTargetProjectId(targetMonitor: targetMonitor)
    let workspace = getOrCreateAdjacentBlankWorkspace(projectId: projectId, monitor: targetMonitor)
    let targetContainer: NonLeafTreeNodeObject
    if sourceNode is Window, sourceWindow.isFloating {
        targetContainer = workspace
    } else {
        targetContainer = workspace.rootTilingContainer
    }
    sourceNode.bind(to: targetContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    return sourceWindow.focusWindow()
}

@MainActor
private func sidebarWorkspaceTargetProjectId(targetMonitor: Monitor) -> WorkspaceProjectId {
    let selectedProjectId = TrayMenuModel.shared.workspaceSidebarSelectedProjectId
    guard workspaceProjects().contains(where: { $0.id == selectedProjectId }) else {
        return activeWorkspaceProjectId(for: targetMonitor)
    }
    return selectedProjectId
}

@MainActor
private func selectWorkspaceSidebarProject(_ projectId: WorkspaceProjectId) {
    guard workspaceProjects().contains(where: { $0.id == projectId }) else { return }
    TrayMenuModel.shared.workspaceSidebarSelectedProjectId = projectId
    runWorkspaceSidebarSession {
        TrayMenuModel.shared.workspaceSidebarSelectedProjectId = projectId
        if let workspace = switchWorkspaceProject(projectId, on: sidebarWorkspaceTargetMonitor()) {
            _ = workspace.focusWorkspace()
        }
    }
}

@MainActor
private func createWorkspaceSidebarProject() {
    runWorkspaceSidebarSession {
        let project = createWorkspaceProject()
        TrayMenuModel.shared.workspaceSidebarSelectedProjectId = project.id
        if let workspace = switchWorkspaceProject(project.id, on: sidebarWorkspaceTargetMonitor()) {
            _ = workspace.focusWorkspace()
        }
    }
}

@MainActor
private func renameWorkspaceSidebarProject(_ project: WorkspaceSidebarProjectViewModel, displayName: String) {
    runWorkspaceSidebarSession {
        try renameWorkspaceProject(project.id, displayName: displayName)
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
private func setWorkspaceSidebarProjectColor(_ project: WorkspaceSidebarProjectViewModel, colorHex: String?) {
    runWorkspaceSidebarSession {
        let normalizedColorHex = colorHex.flatMap(normalizedWorkspaceSidebarColorHex)
        if let normalizedColorHex {
            config.workspaceSidebar.projectColors[project.id.rawValue] = normalizedColorHex
        } else {
            config.workspaceSidebar.projectColors.removeValue(forKey: project.id.rawValue)
        }
        if !isUnitTest {
            try persistWorkspaceSidebarProjectColor(projectId: project.id.rawValue, colorHex: normalizedColorHex)
        }
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
private func deleteWorkspaceSidebarProject(_ project: WorkspaceSidebarProjectViewModel) {
    guard canDeleteWorkspaceProject(project.id) else { return }
    let fallbackProjectId = workspaceProjectFallbackForDeletion(excluding: project.id)
    TrayMenuModel.shared.workspaceSidebarSelectedProjectId = fallbackProjectId
    runWorkspaceSidebarSession {
        try deleteWorkspaceProject(project.id)
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
private func renameWorkspaceFromSidebar(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
    guard let newName = promptWorkspaceSidebarName(title: "Rename Workspace", currentName: workspace.displayName) else { return }
    renameWorkspaceFromSidebar(workspace, displayName: newName)
}

@MainActor
private func renameWorkspaceFromSidebar(_ workspace: WorkspaceSidebarWorkspaceViewModel, displayName: String) {
    runWorkspaceSidebarSession {
        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: displayName)
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
private func resetWorkspaceNameFromSidebar(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
    runWorkspaceSidebarSession {
        try resetWorkspaceSidebarName(workspaceName: workspace.name)
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
private func deleteWorkspaceFromSidebar(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
    runWorkspaceSidebarSession {
        try deleteWorkspaceForSidebar(workspaceName: workspace.name)
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
private func focusWindowFromSidebar(_ windowId: UInt32, fallbackWorkspace: String) {
    runWorkspaceSidebarSession {
        guard let window = Window.get(byId: windowId),
              let liveFocus = window.toLiveFocusOrNil()
        else {
            _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
            return
        }
        _ = setFocus(to: liveFocus)
        window.nativeFocus()
    }
}

@MainActor
private func updateSidebarWindowDrag(_ windowId: UInt32, subject: WindowDragSubject = .window) {
    guard let window = Window.get(byId: windowId) else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    beginWindowMoveWithMouseSessionIfNeeded(
        windowId: window.windowId,
        subject: subject,
        detachOrigin: .window,
        startedInSidebar: true,
        anchorRect: resolvedDraggedWindowAnchorRect(for: window, subject: subject),
        refreshActualRects: subject == .window,
    )
    WindowMouseInteractionDriver.shared.startMove(
        windowId: window.windowId,
        subject: subject,
        detachOrigin: .window,
        startedInSidebar: true,
    )
}

@MainActor
private func finishSidebarWindowDrag() {
    Task { @MainActor in
        try? await resetManipulatedWithMouseIfPossible()
    }
}

struct WorkspaceSidebarView: View {
    @ObservedObject var viewModel: TrayMenuModel
    @State private var projectSwipeTranslation: CGFloat = 0
    @State private var projectSwipeStartProjectId: WorkspaceProjectId? = nil
    @State private var projectSwipeDidCrossBreakPoint = false
    @State private var projectPagerWidth: CGFloat = 0

    var body: some View {
        let collapsedWidth = CGFloat(config.workspaceSidebar.collapsedWidth)
        let expandedWidth = CGFloat(config.workspaceSidebar.width)
        let expansionProgress = max(
            0,
            min(1, (viewModel.workspaceSidebarVisibleWidth - collapsedWidth) / max(expandedWidth - collapsedWidth, 1)),
        )
        
        ZStack(alignment: .leading) {
            sidebarContent(expansionProgress: expansionProgress)
                .frame(width: max(viewModel.workspaceSidebarVisibleWidth, 0), alignment: .leading)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: max(viewModel.workspaceSidebarVisibleWidth, 0))
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.clear)
        .onChange(of: viewModel.workspaceSidebarSelectedProjectId) { _ in
            resetProjectSwipeWithoutAnimation()
        }
        .onChange(of: viewModel.workspaceSidebarProjects) { _ in
            resetProjectSwipeWithoutAnimation()
        }
    }

    private func sidebarContent(expansionProgress: CGFloat) -> some View {
        let isCompact = expansionProgress < workspaceSidebarRowsRevealProgress
        let leadingInset = workspaceSidebarOuterLeadingPadding(isCompact: isCompact)
        let trailingInset = workspaceSidebarOuterTrailingPadding(isCompact: isCompact)
        let showsMonitorSelector = !isCompact && viewModel.workspaceSidebarShowsMonitorSelector
        let projectSwipeDirection = workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: projectSwipeTranslation,
            verticalTranslation: 0,
            minimumDistance: 1,
        )
        let activeProjectIndex = projectPagerDisplayIndex
        let projectSwipeProgress = workspaceSidebarProjectEdgeCreationProgress(
            currentIndex: activeProjectIndex,
            projectCount: viewModel.workspaceSidebarProjects.count,
            direction: projectSwipeDirection,
            distance: abs(projectSwipeTranslation),
        )
        let hasSwipeTarget = projectSwipeDirection.flatMap { direction in
            workspaceSidebarProjectIndexAfterSwipe(
                currentIndex: activeProjectIndex,
                projectCount: viewModel.workspaceSidebarProjects.count,
                direction: direction,
            )
        } != nil
        let projectSwitchProgress = hasSwipeTarget
            ? workspaceSidebarProjectSwipeSwitchProgress(distance: abs(projectSwipeTranslation))
            : 0
        let visibleWorkspacesByProject = workspaceSidebarVisibleWorkspacesByProject(
            workspaces: viewModel.workspaceSidebarWorkspaces,
            selectedScopeId: viewModel.workspaceSidebarSelectedMonitorScopeId,
            focusedMonitorScopeId: viewModel.workspaceSidebarFocusedMonitorScopeId,
        )

        return VStack(alignment: .leading, spacing: 0) {
            if showsMonitorSelector {
                WorkspaceSidebarMonitorSelector(
                    scopes: viewModel.workspaceSidebarMonitorScopes,
                    selectedScopeId: viewModel.workspaceSidebarSelectedMonitorScopeId,
                    expansionProgress: expansionProgress,
                )
                .padding(.leading, leadingInset)
                .padding(.trailing, trailingInset)
                .padding(.top, viewModel.workspaceSidebarTopPadding)
                .padding(.bottom, 6)
            }

            projectPagerContent(
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: showsMonitorSelector ? 0 : viewModel.workspaceSidebarTopPadding,
                visibleWorkspacesByProject: visibleWorkspacesByProject,
                swipeDirection: projectSwipeDirection,
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            WorkspaceSidebarProjectPager(
                projects: viewModel.workspaceSidebarProjects,
                selectedProjectId: viewModel.workspaceSidebarSelectedProjectId,
                expansionProgress: expansionProgress,
                swipeDirection: projectSwipeDirection,
                switchProgress: projectSwitchProgress,
                edgeProgress: projectSwipeProgress,
            )
            .zIndex(2)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.top, 6)
            .padding(.bottom, 2)

            WorkspaceSidebarStatusView(
                sectionWidth: workspaceSidebarSectionWidth(expansionProgress),
                isCompact: isCompact,
            )
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.top, 8)
            .padding(.bottom, workspaceSidebarStatusBottomPadding(isCompact: isCompact))
        }
        .coordinateSpace(name: "workspaceSidebarContent")
        .onPreferenceChange(WorkspaceSidebarDropTargetPreferenceKey.self) { frames in
            WorkspaceSidebarPanel.shared.updateDropTargets(frames)
        }
        .background {
            sidebarSurface(in: sidebarShape)
        }
        .environment(\.colorScheme, .dark)
        .clipShape(sidebarShape)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(mattePanelSeparator.opacity(0.72))
                .frame(width: 0.5)
        }
        .shadow(
            color: Color.black.opacity(0.28),
            radius: 14,
            x: 2,
            y: 0
        )
        .overlay {
            WorkspaceSidebarProjectSwipeScrollCapture(
                isEnabled: !viewModel.workspaceSidebarProjects.isEmpty,
                onChanged: { horizontalTranslation, verticalTranslation in
                    handleProjectSwipeChanged(
                        horizontalTranslation: horizontalTranslation,
                        verticalTranslation: verticalTranslation,
                        expansionProgress: expansionProgress,
                    )
                },
                onEnded: { horizontalTranslation, verticalTranslation in
                    handleProjectSwipeEnded(
                        horizontalTranslation: horizontalTranslation,
                        verticalTranslation: verticalTranslation,
                        expansionProgress: expansionProgress,
                    )
                },
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
        .simultaneousGesture(projectSwipeGesture(expansionProgress: expansionProgress))
    }

    private var sidebarShape: some Shape {
        Rectangle()
    }

    private func sidebarSurface<S: Shape>(in shape: S) -> some View {
        shape
            .fill(mattePanelFill)
            .overlay {
                shape.stroke(mattePanelSeparator.opacity(0.34), lineWidth: 0.5)
            }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func projectPagerContent(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        visibleWorkspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
        swipeDirection: Int?,
    ) -> some View {
        if viewModel.workspaceSidebarProjects.isEmpty {
            workspacePage(
                workspaces: visibleWorkspacesByProject[viewModel.workspaceSidebarSelectedProjectId] ?? [],
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                isInteractive: true,
            )
        } else {
            GeometryReader { geometry in
                let pageWidth = max(geometry.size.width, 1)
                let displayIndex = projectPagerDisplayIndex ?? 0
                let dragOffset = workspaceSidebarProjectPagerDragOffset(
                    horizontalTranslation: projectSwipeTranslation,
                    currentIndex: displayIndex,
                    projectCount: viewModel.workspaceSidebarProjects.count,
                    pageWidth: pageWidth,
                )

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(viewModel.workspaceSidebarProjects.enumerated()), id: \.element.id) { index, project in
                        if shouldRenderWorkspaceSidebarProjectPage(
                            index: index,
                            displayIndex: displayIndex,
                            swipeDirection: swipeDirection,
                            projectCount: viewModel.workspaceSidebarProjects.count,
                        ) {
                            workspacePage(
                                workspaces: visibleWorkspacesByProject[project.id] ?? [],
                                expansionProgress: expansionProgress,
                                leadingInset: leadingInset,
                                trailingInset: trailingInset,
                                topPadding: topPadding,
                                isInteractive: index == displayIndex,
                            )
                            .frame(width: pageWidth, alignment: .topLeading)
                            .allowsHitTesting(index == displayIndex)
                        } else {
                            Color.clear
                                .frame(width: pageWidth, alignment: .topLeading)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .offset(x: -CGFloat(displayIndex) * pageWidth + dragOffset)
                .onAppear {
                    projectPagerWidth = pageWidth
                }
                .onChange(of: pageWidth) { width in
                    projectPagerWidth = width
                }
            }
            .clipped()
        }
    }

    private func workspacePage(
        workspaces: [WorkspaceSidebarWorkspaceViewModel],
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        isInteractive: Bool,
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(workspaces) { workspace in
                    WorkspaceSidebarWorkspaceSection(
                        workspace: workspace,
                        dragPreview: viewModel.workspaceSidebarDropPreview,
                        expansionProgress: expansionProgress,
                        emitsDropTarget: isInteractive,
                    )
                }
                WorkspaceSidebarCreateWorkspaceSection(
                    dragPreview: viewModel.workspaceSidebarDropPreview,
                    expansionProgress: expansionProgress,
                    emitsDropTarget: isInteractive,
                    onCreateWorkspace: createWorkspaceFromSidebarButton,
                )
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.top, topPadding)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var selectedProjectIndex: Int? {
        viewModel.workspaceSidebarProjects.firstIndex { $0.id == viewModel.workspaceSidebarSelectedProjectId }
            ?? viewModel.workspaceSidebarProjects.indices.first
    }

    private var projectPagerDisplayIndex: Int? {
        if let projectSwipeStartProjectId,
           let index = viewModel.workspaceSidebarProjects.firstIndex(where: { $0.id == projectSwipeStartProjectId }) {
            return index
        }
        return selectedProjectIndex
    }

    private func projectSwipeGesture(expansionProgress: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                handleProjectSwipeChanged(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height,
                    expansionProgress: expansionProgress,
                )
            }
            .onEnded { value in
                handleProjectSwipeEnded(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height,
                    expansionProgress: expansionProgress,
                )
            }
    }

    private func handleProjectSwipeChanged(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) {
        guard shouldHandleProjectSwipe(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
            expansionProgress: expansionProgress,
        ) else {
            resetProjectSwipe()
            return
        }
        if projectSwipeStartProjectId == nil,
           let selectedProjectIndex {
            projectSwipeStartProjectId = viewModel.workspaceSidebarProjects[selectedProjectIndex].id
        }
        projectSwipeTranslation = horizontalTranslation
        guard let direction = workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
        ) else {
            return
        }
        let activeProjectIndex = projectPagerDisplayIndex
        let shouldCreate = shouldCreateWorkspaceSidebarProjectAfterSwipe(
            currentIndex: activeProjectIndex,
            projectCount: viewModel.workspaceSidebarProjects.count,
            direction: direction,
            distance: abs(horizontalTranslation),
        )
        let shouldNavigate =
            workspaceSidebarProjectIndexAfterSwipe(
                currentIndex: activeProjectIndex,
                projectCount: viewModel.workspaceSidebarProjects.count,
                direction: direction,
            ) != nil &&
            abs(horizontalTranslation) >= workspaceSidebarProjectSwipeNavigateThreshold
        let shouldCommit = shouldCreate || shouldNavigate
        if shouldCommit && !projectSwipeDidCrossBreakPoint {
            projectSwipeDidCrossBreakPoint = true
            performWorkspaceSidebarProjectHaptic(.alignment)
        } else if !shouldCommit {
            projectSwipeDidCrossBreakPoint = false
        }
    }

    private func handleProjectSwipeEnded(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) {
        guard shouldHandleProjectSwipe(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
            expansionProgress: expansionProgress,
        ),
              let direction = workspaceSidebarProjectSwipeDirection(
                horizontalTranslation: horizontalTranslation,
                verticalTranslation: verticalTranslation,
              )
        else {
            finishProjectSwipeSnapBack()
            return
        }
        if projectSwipeStartProjectId == nil,
           let selectedProjectIndex {
            projectSwipeStartProjectId = viewModel.workspaceSidebarProjects[selectedProjectIndex].id
        }
        let activeProjectIndex = projectPagerDisplayIndex
        if shouldCreateWorkspaceSidebarProjectAfterSwipe(
            currentIndex: activeProjectIndex,
            projectCount: viewModel.workspaceSidebarProjects.count,
            direction: direction,
            distance: abs(horizontalTranslation),
        ) {
            performWorkspaceSidebarProjectHaptic(.levelChange)
            finishProjectSwipeCreation()
            return
        }
        guard let nextIndex = workspaceSidebarProjectIndexAfterSwipe(
            currentIndex: activeProjectIndex,
            projectCount: viewModel.workspaceSidebarProjects.count,
            direction: direction,
        ), abs(horizontalTranslation) >= workspaceSidebarProjectSwipeNavigateThreshold else {
            performWorkspaceSidebarProjectHaptic(.alignment)
            finishProjectSwipeSnapBack()
            return
        }
        finishProjectSwipeNavigation(
            to: viewModel.workspaceSidebarProjects[nextIndex].id,
            direction: direction,
        )
    }

    private func shouldHandleProjectSwipe(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) -> Bool {
        guard !viewModel.workspaceSidebarProjects.isEmpty,
              !isWorkspaceSidebarDragInProgress()
        else {
            return false
        }
        return workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
        ) != nil
    }

    private func resetProjectSwipe() {
        projectSwipeTranslation = 0
        projectSwipeStartProjectId = nil
        projectSwipeDidCrossBreakPoint = false
    }

    private func resetProjectSwipeWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            resetProjectSwipe()
        }
    }

    private func finishProjectSwipeSnapBack() {
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.9)) {
            resetProjectSwipe()
        }
    }

    private func finishProjectSwipeNavigation(to projectId: WorkspaceProjectId, direction: Int) {
        let startProjectId = projectSwipeStartProjectId
        let fullPageOffset = -CGFloat(direction) * max(projectPagerWidth, CGFloat(config.workspaceSidebar.width), 1)
        withAnimation(.easeOut(duration: 0.12)) {
            projectSwipeTranslation = fullPageOffset
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard projectSwipeStartProjectId == startProjectId else { return }
            selectWorkspaceSidebarProject(projectId)
            resetProjectSwipeWithoutAnimation()
        }
    }

    private func finishProjectSwipeCreation() {
        withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.9)) {
            resetProjectSwipe()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard projectSwipeStartProjectId == nil else { return }
            createWorkspaceSidebarProject()
        }
    }

    private func performWorkspaceSidebarProjectHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

private struct WorkspaceSidebarProjectSwipeScrollCapture: NSViewRepresentable {
    let isEnabled: Bool
    let onChanged: (CGFloat, CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.view = view
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        if isEnabled {
            context.coordinator.installMonitor()
        } else {
            context.coordinator.removeMonitor()
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var isEnabled = false
        var onChanged: ((CGFloat, CGFloat) -> Void)?
        var onEnded: ((CGFloat, CGFloat) -> Void)?
        private var monitor: Any?
        private var horizontalTranslation: CGFloat = 0
        private var verticalTranslation: CGFloat = 0
        private var hasLockedHorizontalIntent = false
        private var endWorkItem: DispatchWorkItem?

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            resetAccumulatedScroll()
        }

        func resetAccumulatedScroll() {
            endWorkItem?.cancel()
            endWorkItem = nil
            horizontalTranslation = 0
            verticalTranslation = 0
            hasLockedHorizontalIntent = false
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled,
                  event.hasPreciseScrollingDeltas,
                  event.momentumPhase.isEmpty,
                  let view,
                  let window = view.window,
                  event.window === window
            else {
                resetIfNeededForExternalEvent(event)
                return event
            }
            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point) else {
                resetIfNeededForExternalEvent(event)
                return event
            }
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                resetAccumulatedScroll()
            }
            horizontalTranslation = workspaceSidebarProjectSwipeTranslationAfterScroll(
                currentTranslation: horizontalTranslation,
                scrollingDeltaX: event.scrollingDeltaX,
            )
            verticalTranslation += event.scrollingDeltaY

            if !hasLockedHorizontalIntent {
                guard workspaceSidebarProjectSwipeDirection(
                    horizontalTranslation: horizontalTranslation,
                    verticalTranslation: verticalTranslation,
                ) != nil else {
                    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                        resetAccumulatedScroll()
                    }
                    return event
                }
                hasLockedHorizontalIntent = true
            }

            onChanged?(horizontalTranslation, verticalTranslation)
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                finishLockedSwipe()
            } else {
                scheduleEndTimer()
            }
            return nil
        }

        private func resetIfNeededForExternalEvent(_ event: NSEvent) {
            guard hasLockedHorizontalIntent,
                  event.phase.contains(.ended) || event.phase.contains(.cancelled)
            else {
                return
            }
            finishLockedSwipe()
        }

        private func scheduleEndTimer() {
            endWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.finishLockedSwipe()
            }
            endWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        }

        private func finishLockedSwipe() {
            guard hasLockedHorizontalIntent else {
                resetAccumulatedScroll()
                return
            }
            let finalHorizontalTranslation = horizontalTranslation
            let finalVerticalTranslation = verticalTranslation
            resetAccumulatedScroll()
            onEnded?(finalHorizontalTranslation, finalVerticalTranslation)
        }
    }
}

// MARK: - Monitor Selector

struct WorkspaceSidebarMonitorSelector: View {
    let scopes: [WorkspaceSidebarMonitorScopeViewModel]
    let selectedScopeId: String
    let expansionProgress: CGFloat

    @State private var hoveredScopeId: String? = nil

    private var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(scopes) { scope in
                    Button {
                        selectWorkspaceSidebarMonitorScope(scope.id)
                    } label: {
                        scopeLabel(scope)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(scopeAccessibilityLabel(scope))
                    .onHover { hover in
                        hoveredScopeId = hover ? scope.id : (hoveredScopeId == scope.id ? nil : hoveredScopeId)
                    }
                    .background {
                        if workspaceSidebarMonitorScopePoint(scope.id) != nil {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: WorkspaceSidebarDropTargetPreferenceKey.self,
                                    value: [WorkspaceSidebarDropTargetFrame(
                                        kind: .monitor(scope.id),
                                        frame: geometry.frame(in: .named("workspaceSidebarContent")),
                                    )],
                                )
                            }
                        }
                    }
                }
            }
            .frame(minWidth: sectionWidth, alignment: .leading)
        }
        .frame(width: sectionWidth, height: 30, alignment: .leading)
        .clipped()
    }

    private func scopeLabel(_ scope: WorkspaceSidebarMonitorScopeViewModel) -> some View {
        let isSelected = selectedScopeId == scope.id
        let isHovered = hoveredScopeId == scope.id
        return HStack(spacing: 5) {
            Image(systemName: scope.systemImageName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 12, height: 12)
            Text(scope.displayName)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
            if scope.isFocusedMonitor && scope.id != workspaceSidebarFocusedScopeId {
                Circle()
                    .fill(Color.accentColor.opacity(isSelected ? 0.95 : 0.72))
                    .frame(width: 4, height: 4)
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.72))
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            Capsule(style: .continuous)
                .fill(scopeFill(isSelected: isSelected, isHovered: isHovered))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(scopeBorder(isSelected: isSelected, isHovered: isHovered), lineWidth: 0.5)
                }
        )
        .contentShape(Capsule(style: .continuous))
    }

    private func scopeFill(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.22)
        }
        if isHovered {
            return Color.white.opacity(0.07)
        }
        return Color.white.opacity(0.035)
    }

    private func scopeBorder(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.36)
        }
        return Color.white.opacity(isHovered ? 0.10 : 0.06)
    }

    private func scopeAccessibilityLabel(_ scope: WorkspaceSidebarMonitorScopeViewModel) -> String {
        if let subtitle = scope.subtitle {
            return "\(scope.displayName), \(subtitle)"
        }
        return scope.displayName
    }
}

// MARK: - Project Pager

struct WorkspaceSidebarProjectPager: View {
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId
    let expansionProgress: CGFloat
    let swipeDirection: Int?
    let switchProgress: CGFloat
    let edgeProgress: CGFloat

    @State private var isHovered = false
    @State private var pressedProjectId: WorkspaceProjectId? = nil
    @State private var editingProjectId: WorkspaceProjectId? = nil
    @State private var editingProjectDraft = ""

    private var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress) }
    private var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    private var currentIndex: Int? {
        projects.firstIndex { $0.id == selectedProjectId }
            ?? projects.indices.first
    }
    private var selectedProject: WorkspaceSidebarProjectViewModel? {
        projects.first { $0.id == selectedProjectId }
            ?? projects.first
    }
    private var swipeTargetIndex: Int? {
        guard let swipeDirection else { return nil }
        return workspaceSidebarProjectIndexAfterSwipe(
            currentIndex: currentIndex,
            projectCount: projects.count,
            direction: swipeDirection,
        )
    }
    private var footerSpacing: CGFloat { isCompact ? 2 : 8 }
    private var projectMenuWidth: CGFloat {
        let selectedProjectName = selectedProject?.displayName ?? "Project"
        let textWidth = (selectedProjectName as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .medium)],
        ).width
        return min(max(ceil(textWidth) + 46, 92), 136)
    }
    private var projectTrackWidth: CGFloat {
        if isCompact {
            return max(sectionWidth - 4, 12)
        }
        return max(sectionWidth - projectMenuWidth - footerSpacing, 24)
    }

    var body: some View {
        if !projects.isEmpty {
            pagerContent
                .frame(width: sectionWidth, height: workspaceSidebarPagerHeight, alignment: .center)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("New") {
                        createWorkspaceSidebarProject()
                    }
                }
                .onHover { hovering in
                    isHovered = hovering
                }
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: isHovered)
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: currentIndex)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.88), value: edgeProgress)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
        }
    }

    private var pagerContent: some View {
        Group {
            if isCompact {
                compactProjectIndicator
            } else {
                HStack(alignment: .center, spacing: footerSpacing) {
                    projectDotTrack
                    projectMenu
                        .frame(width: projectMenuWidth, height: workspaceSidebarPagerHeight, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, isCompact ? 2 : 0)
        .frame(width: sectionWidth, height: workspaceSidebarPagerHeight, alignment: .center)
    }

    private func beginInlineRename(_ project: WorkspaceSidebarProjectViewModel) {
        if selectedProjectId != project.id {
            selectWorkspaceSidebarProject(project.id)
        }
        WorkspaceSidebarPanel.shared.beginInlineTextEditing()
        editingProjectId = project.id
        editingProjectDraft = project.displayName
    }

    private func commitInlineRename(_ project: WorkspaceSidebarProjectViewModel) {
        guard editingProjectId == project.id else { return }
        let trimmed = editingProjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        editingProjectId = nil
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
        guard !trimmed.isEmpty, trimmed != project.displayName else { return }
        renameWorkspaceSidebarProject(project, displayName: trimmed)
    }

    private func cancelInlineRename() {
        editingProjectId = nil
        editingProjectDraft = ""
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
    }

    @ViewBuilder
    private var compactProjectIndicator: some View {
        if let selectedProject, let currentIndex {
            projectDot(
                selectedProject,
                index: currentIndex,
                swipeProgress: 1,
                edgeProgress: dotEdgeProgress(for: currentIndex),
            )
            .frame(width: sectionWidth, height: workspaceSidebarPagerHeight, alignment: .center)
        }
    }

    private var projectDotTrack: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 6) {
                ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                    projectDot(
                        project,
                        index: index,
                        swipeProgress: dotSwipeProgress(for: index),
                        edgeProgress: dotEdgeProgress(for: index),
                    )
                }
            }
            .padding(.horizontal, isCompact ? 2 : 5)
            .frame(minWidth: projectTrackWidth, minHeight: workspaceSidebarPagerHeight, alignment: .center)
        }
        .frame(width: projectTrackWidth, height: workspaceSidebarPagerHeight, alignment: .center)
        .clipped()
    }

    @ViewBuilder
    private var projectMenu: some View {
        if let selectedProject, editingProjectId == selectedProject.id {
            projectMenuInlineEditor(selectedProject)
        } else {
            WorkspaceSidebarProjectMenuButton(
                projects: projects,
                selectedProjectId: selectedProjectId,
                selectedProjectName: selectedProject?.displayName ?? "Project",
                width: projectMenuWidth,
                isHovered: isHovered,
                canDeleteSelectedProject: selectedProject.map { canDeleteWorkspaceProject($0.id) } ?? false,
                onSelectProject: { projectId in
                    selectWorkspaceSidebarProject(projectId)
                },
                onCreateProject: {
                    createWorkspaceSidebarProject()
                },
                onRenameSelectedProject: {
                    if let selectedProject {
                        beginInlineRename(selectedProject)
                    }
                },
                onSetSelectedProjectColor: { colorHex in
                    if let selectedProject {
                        setWorkspaceSidebarProjectColor(selectedProject, colorHex: colorHex)
                    }
                },
                onDeleteSelectedProject: {
                    if let selectedProject {
                        deleteWorkspaceSidebarProject(selectedProject)
                    }
                },
            )
            .frame(width: projectMenuWidth, height: workspaceSidebarPagerHeight, alignment: .leading)
            .contextMenu {
                if let selectedProject {
                    projectContextMenuItems(for: selectedProject)
                }
            }
        }
    }

    @ViewBuilder
    private func projectContextMenuItems(for project: WorkspaceSidebarProjectViewModel) -> some View {
        Button("Rename Project") {
            beginInlineRename(project)
        }
        Menu("Color") {
            let selectedColorHex = project.colorHex.flatMap(normalizedWorkspaceSidebarColorHex)
            Button {
                setWorkspaceSidebarProjectColor(project, colorHex: nil)
            } label: {
                Label {
                    Text("Auto")
                } icon: {
                    Image(nsImage: workspaceSidebarAutomaticColorSwatchImage(isSelected: selectedColorHex == nil))
                }
            }
            Divider()
            ForEach(workspaceSidebarProjectColorPresets) { preset in
                Button {
                    setWorkspaceSidebarProjectColor(project, colorHex: preset.hex)
                } label: {
                    Label {
                        Text(preset.name)
                    } icon: {
                        Image(nsImage: workspaceSidebarProjectColorSwatchImage(
                            hex: preset.hex,
                            isSelected: selectedColorHex == preset.hex,
                        ))
                    }
                }
            }
        }
        Button(role: .destructive) {
            deleteWorkspaceSidebarProject(project)
        } label: {
            Text("Delete Project")
        }
        .disabled(!canDeleteWorkspaceProject(project.id))
    }

    private func projectMenuInlineEditor(_ project: WorkspaceSidebarProjectViewModel) -> some View {
        WorkspaceSidebarProjectRenameField(
            text: $editingProjectDraft,
            focusId: project.id.rawValue,
            alignment: .left,
            fontSize: 11.5,
            fontWeight: .semibold,
            onCommit: {
                commitInlineRename(project)
            },
            onCancel: cancelInlineRename,
        )
            .padding(.horizontal, 7)
            .frame(width: projectMenuWidth, height: 28, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 0.5)
                    }
            )
    }

    @ViewBuilder
    private func projectDot(
        _ project: WorkspaceSidebarProjectViewModel,
        index: Int,
        swipeProgress: CGFloat,
        edgeProgress: CGFloat,
    ) -> some View {
        let isCurrent = index == currentIndex
        let isSwipeTarget = index == swipeTargetIndex
        let isPressed = pressedProjectId == project.id
        let projectColor = workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex)
        if editingProjectId == project.id && isCompact {
            WorkspaceSidebarProjectRenameField(
                text: $editingProjectDraft,
                focusId: project.id.rawValue,
                alignment: .center,
                fontSize: 11,
                fontWeight: .semibold,
                onCommit: {
                    commitInlineRename(project)
                },
                onCancel: cancelInlineRename,
            )
                .frame(width: 86, height: 24)
                .padding(.horizontal, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.26))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5)
                        }
                )
        } else {
            Button {
                selectWorkspaceSidebarProject(project.id)
            } label: {
                Capsule(style: .continuous)
                    .fill(dotFill(
                        isCurrent: isCurrent,
                        isSwipeTarget: isSwipeTarget,
                        swipeProgress: swipeProgress,
                        edgeProgress: edgeProgress,
                        projectColor: projectColor,
                    ))
                    .frame(
                        width: dotWidth(
                            isCurrent: isCurrent,
                            isSwipeTarget: isSwipeTarget,
                            swipeProgress: swipeProgress,
                            edgeProgress: edgeProgress,
                        ),
                        height: dotHeight(
                            isCurrent: isCurrent,
                            isSwipeTarget: isSwipeTarget,
                            swipeProgress: swipeProgress,
                            edgeProgress: edgeProgress,
                        ),
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(dotBorder(
                                isCurrent: isCurrent,
                                isSwipeTarget: isSwipeTarget,
                                swipeProgress: swipeProgress,
                                edgeProgress: edgeProgress,
                                projectColor: projectColor,
                            ), lineWidth: 0.5)
                    }
                    .scaleEffect(isPressed ? 0.96 : 1)
                    .frame(width: dotHitWidth(
                        isCurrent: isCurrent,
                        isSwipeTarget: isSwipeTarget,
                        swipeProgress: swipeProgress,
                        edgeProgress: edgeProgress,
                    ), height: dotHitHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(project.displayName)
            .help(project.displayName)
            .contextMenu {
                projectContextMenuItems(for: project)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressedProjectId = project.id }
                    .onEnded { _ in pressedProjectId = nil },
            )
            .onTapGesture(count: 2) {
                beginInlineRename(project)
            }
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: swipeProgress)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.84), value: isCurrent)
            .animation(.easeOut(duration: 0.14), value: isPressed)
        }
    }

    private func dotSwipeProgress(for index: Int) -> CGFloat {
        let progress = min(max(switchProgress, 0), 1)
        if index == swipeTargetIndex {
            return progress
        }
        if index == currentIndex {
            return swipeTargetIndex == nil && swipeDirection != nil ? 1 : 1 - progress * 0.55
        }
        return 0
    }

    private func dotEdgeProgress(for index: Int) -> CGFloat {
        guard index == currentIndex,
              swipeTargetIndex == nil,
              swipeDirection != nil
        else {
            return 0
        }
        return min(max(edgeProgress, 0), 1)
    }

    private func dotWidth(isCurrent: Bool, isSwipeTarget: Bool, swipeProgress: CGFloat, edgeProgress: CGFloat) -> CGFloat {
        if isCompact {
            if isCurrent {
                return 18 + 6 * edgeProgress
            }
            if isSwipeTarget {
                return 9 + 9 * swipeProgress
            }
            return 9
        }
        if isCurrent {
            return 18 * max(swipeProgress, 0.45) + 8 * edgeProgress
        }
        if isSwipeTarget {
            return 7 + 15 * swipeProgress
        }
        return 8
    }

    private func dotHeight(isCurrent: Bool, isSwipeTarget: Bool, swipeProgress: CGFloat, edgeProgress: CGFloat) -> CGFloat {
        if isCompact {
            return 9
        }
        if isCurrent || isSwipeTarget {
            return 7 + 1.5 * swipeProgress + edgeProgress
        }
        return 7
    }

    private func dotHitWidth(isCurrent: Bool, isSwipeTarget: Bool, swipeProgress: CGFloat, edgeProgress: CGFloat) -> CGFloat {
        let visibleWidth = dotWidth(
            isCurrent: isCurrent,
            isSwipeTarget: isSwipeTarget,
            swipeProgress: swipeProgress,
            edgeProgress: edgeProgress,
        )
        if isCompact {
            return max(visibleWidth, 18)
        }
        return max(visibleWidth + 18, 34)
    }

    private var dotHitHeight: CGFloat {
        isCompact ? 28 : 34
    }

    private func dotFill(
        isCurrent: Bool,
        isSwipeTarget: Bool,
        swipeProgress: CGFloat,
        edgeProgress: CGFloat,
        projectColor: Color,
    ) -> Color {
        if isCompact {
            if isCurrent {
                return projectColor.opacity(0.86 + 0.14 * edgeProgress)
            }
            if isSwipeTarget {
                return projectColor.opacity(0.46 + 0.38 * swipeProgress)
            }
            return projectColor.opacity(isHovered ? 0.58 : 0.42)
        }
        if isCurrent {
            return projectColor.opacity(min(0.42 + 0.42 * max(swipeProgress, 0) + 0.10 * edgeProgress, 1))
        }
        if isSwipeTarget {
            return projectColor.opacity(0.26 + 0.54 * swipeProgress)
        }
        return projectColor.opacity(isHovered ? 0.34 : 0.22)
    }

    private func dotBorder(
        isCurrent: Bool,
        isSwipeTarget: Bool,
        swipeProgress: CGFloat,
        edgeProgress: CGFloat,
        projectColor: Color,
    ) -> Color {
        if isCompact {
            if isCurrent || isSwipeTarget {
                return projectColor.opacity(0.95)
            }
            return Color.white.opacity(isHovered ? 0.16 : 0.08)
        }
        if isCurrent || isSwipeTarget {
            return projectColor.opacity(0.55 + 0.18 * swipeProgress + 0.14 * edgeProgress)
        }
        return projectColor.opacity(isHovered ? 0.32 : 0.20)
    }

    private func dotShadow(
        isCurrent: Bool,
        isSwipeTarget: Bool,
        swipeProgress: CGFloat,
        edgeProgress: CGFloat,
        projectColor: Color,
    ) -> Color {
        if isCompact {
            if isCurrent || isSwipeTarget {
                return projectColor.opacity(0.18 + 0.12 * max(swipeProgress, edgeProgress))
            }
            return Color.clear
        }
        if isCurrent || isSwipeTarget {
            return projectColor.opacity(0.14 + 0.18 * swipeProgress + 0.12 * edgeProgress)
        }
        return Color.clear
    }
}

private final class WorkspaceSidebarProjectMenuControl: NSControl {
    private let pillLayer = CALayer()
    private let titleField = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    private var isExternallyHovered = false
    private var isPressed = false
    private var preferredSize = NSSize(width: 92, height: workspaceSidebarPagerHeight)

    override var intrinsicContentSize: NSSize {
        preferredSize
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        pillLayer.masksToBounds = true
        layer?.addSublayer(pillLayer)

        titleField.font = .systemFont(ofSize: 11.5, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.backgroundColor = .clear
        titleField.isBordered = false
        titleField.isEditable = false
        titleField.isSelectable = false
        addSubview(titleField)

        chevronView.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevronView.symbolConfiguration = .init(pointSize: 8.5, weight: .semibold)
        chevronView.imageScaling = .scaleProportionallyDown
        addSubview(chevronView)

        toolTip = "Projects"
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel("Projects")
        update(title: "Project", width: preferredSize.width, isHovered: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        return self
    }

    func update(title: String, width: CGFloat, isHovered: Bool) {
        let resolvedWidth = max(width, 1)
        let resolvedHeight = max(bounds.height, workspaceSidebarPagerHeight)
        let nextSize = NSSize(width: resolvedWidth, height: resolvedHeight)
        if preferredSize != nextSize {
            preferredSize = nextSize
            invalidateIntrinsicContentSize()
        }
        titleField.stringValue = title
        isExternallyHovered = isHovered
        updateColors()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let pillHeight = min(bounds.height, 26)
        let pillFrame = CGRect(
            x: 0,
            y: (bounds.height - pillHeight) / 2,
            width: bounds.width,
            height: pillHeight,
        )
        pillLayer.frame = pillFrame
        pillLayer.cornerRadius = pillHeight / 2

        let horizontalInset: CGFloat = 10
        let chevronSize: CGFloat = 11
        let chevronGap: CGFloat = 6
        let titleMaxWidth = max(bounds.width - horizontalInset * 2 - chevronSize - chevronGap, 12)
        let titleWidth = min(ceil(titleField.intrinsicContentSize.width) + 6, titleMaxWidth)
        let titleHeight: CGFloat = 16
        titleField.frame = NSRect(
            x: pillFrame.minX + horizontalInset,
            y: pillFrame.midY - titleHeight / 2 - 0.5,
            width: titleWidth,
            height: titleHeight,
        )

        chevronView.frame = NSRect(
            x: pillFrame.maxX - horizontalInset - chevronSize,
            y: pillFrame.midY - chevronSize / 2 - 0.5,
            width: chevronSize,
            height: chevronSize,
        )
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateColors()
        sendAction(action, to: target)
        isPressed = false
        updateColors()
    }

    private func updateColors() {
        let textAlpha: CGFloat = isPressed ? 0.90 : isExternallyHovered ? 0.82 : 0.72
        titleField.textColor = NSColor.white.withAlphaComponent(textAlpha)
        chevronView.contentTintColor = NSColor.white.withAlphaComponent(textAlpha)
        pillLayer.backgroundColor = NSColor.white.withAlphaComponent(isPressed ? 0.095 : 0.065).cgColor
        pillLayer.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
        pillLayer.borderWidth = 0.5
    }
}

private struct WorkspaceSidebarProjectMenuButton: NSViewRepresentable {
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId
    let selectedProjectName: String
    let width: CGFloat
    let isHovered: Bool
    let canDeleteSelectedProject: Bool
    let onSelectProject: (WorkspaceProjectId) -> Void
    let onCreateProject: () -> Void
    let onRenameSelectedProject: () -> Void
    let onSetSelectedProjectColor: (String?) -> Void
    let onDeleteSelectedProject: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WorkspaceSidebarProjectMenuControl {
        let control = WorkspaceSidebarProjectMenuControl()
        control.target = context.coordinator
        control.action = #selector(Coordinator.openMenu(_:))
        return control
    }

    func updateNSView(_ control: WorkspaceSidebarProjectMenuControl, context: Context) {
        context.coordinator.parent = self
        control.update(title: selectedProjectName, width: width, isHovered: isHovered)
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        private static let automaticColorValue = "__automatic__"

        var parent: WorkspaceSidebarProjectMenuButton
        private var activeMenu: NSMenu?

        init(_ parent: WorkspaceSidebarProjectMenuButton) {
            self.parent = parent
        }

        @objc func openMenu(_ sender: WorkspaceSidebarProjectMenuControl) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.showsStateColumn = false
            menu.delegate = self

            for project in parent.projects {
                let item = NSMenuItem(
                    title: project.displayName,
                    action: #selector(selectProject(_:)),
                    keyEquivalent: "",
                )
                item.target = self
                item.representedObject = project.id
                menu.addItem(item)
            }

            if !parent.projects.isEmpty {
                menu.addItem(.separator())
            }

            let newItem = NSMenuItem(title: "New", action: #selector(createProject(_:)), keyEquivalent: "")
            newItem.target = self
            menu.addItem(newItem)

            menu.update()
            let menuSize = menu.size
            let x = min(0, sender.bounds.width - menuSize.width)
            let y = sender.bounds.height + menuSize.height + 4
            activeMenu = menu
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: x, y: y),
                in: sender,
            )
        }

        func menuDidClose(_ menu: NSMenu) {
            activeMenu = nil
        }

        @objc private func selectProject(_ item: NSMenuItem) {
            guard let projectId = item.representedObject as? WorkspaceProjectId else { return }
            parent.onSelectProject(projectId)
        }

        @objc private func createProject(_ item: NSMenuItem) {
            parent.onCreateProject()
        }

        @objc private func renameProject(_ item: NSMenuItem) {
            parent.onRenameSelectedProject()
        }

        @objc private func setColor(_ item: NSMenuItem) {
            guard let value = item.representedObject as? String else { return }
            parent.onSetSelectedProjectColor(value == Self.automaticColorValue ? nil : value)
        }

        @objc private func deleteProject(_ item: NSMenuItem) {
            parent.onDeleteSelectedProject()
        }

        private func colorMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false

            let automaticItem = NSMenuItem(title: "Auto", action: #selector(setColor(_:)), keyEquivalent: "")
            automaticItem.target = self
            automaticItem.representedObject = Self.automaticColorValue
            automaticItem.state = selectedProjectColorHex == nil ? .on : .off
            automaticItem.image = workspaceSidebarAutomaticColorSwatchImage(isSelected: selectedProjectColorHex == nil)
            menu.addItem(automaticItem)

            menu.addItem(.separator())

            for preset in workspaceSidebarProjectColorPresets {
                let item = NSMenuItem(title: preset.name, action: #selector(setColor(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.hex
                item.state = selectedProjectColorHex == preset.hex ? .on : .off
                item.image = workspaceSidebarProjectColorSwatchImage(
                    hex: preset.hex,
                    isSelected: selectedProjectColorHex == preset.hex,
                )
                menu.addItem(item)
            }

            return menu
        }

        private var selectedProjectColorHex: String? {
            parent.projects
                .first { $0.id == parent.selectedProjectId }?
                .colorHex
                .flatMap(normalizedWorkspaceSidebarColorHex)
        }
    }
}

private struct WorkspaceSidebarProjectRenameField: NSViewRepresentable {
    @Binding var text: String
    let focusId: String
    let alignment: NSTextAlignment
    let fontSize: CGFloat
    let fontWeight: NSFont.Weight
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WorkspaceSidebarRenameTextField {
        let field = WorkspaceSidebarRenameTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        return field
    }

    func updateNSView(_ field: WorkspaceSidebarRenameTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
        context.coordinator.field = field
        context.coordinator.installOutsideInteractionMonitor(for: field)
        field.onCommit = {
            context.coordinator.commit()
        }
        field.onCancel = {
            context.coordinator.cancel()
        }
        field.alignment = alignment
        field.font = .systemFont(ofSize: fontSize, weight: fontWeight)
        field.textColor = .white
        if field.stringValue != text {
            field.stringValue = text
        }
        guard context.coordinator.focusId != focusId else { return }
        context.coordinator.focusId = focusId
        context.coordinator.didResolve = false
        DispatchQueue.main.async {
            WorkspaceSidebarPanel.shared.prepareForInlineTextEditing()
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }

    static func dismantleNSView(_ field: WorkspaceSidebarRenameTextField, coordinator: Coordinator) {
        coordinator.removeOutsideInteractionMonitor()
        field.onCommit = nil
        field.onCancel = nil
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: WorkspaceSidebarProjectRenameField
        var focusId: String?
        var didResolve = false
        var onCommit: (() -> Void)?
        var onCancel: (() -> Void)?
        weak var field: WorkspaceSidebarRenameTextField?
        private var outsideInteractionMonitor: Any?

        init(_ parent: WorkspaceSidebarProjectRenameField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func installOutsideInteractionMonitor(for field: WorkspaceSidebarRenameTextField) {
            guard outsideInteractionMonitor == nil else { return }
            outsideInteractionMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown],
            ) { [weak self, weak field] event in
                guard let self, let field else { return event }
                if event.type == .keyDown, event.keyCode == 53 {
                    self.cancel()
                    return nil
                }
                if event.type == .keyDown {
                    return event
                }
                guard event.window === field.window else {
                    self.commit()
                    return event
                }
                let localPoint = field.convert(event.locationInWindow, from: nil)
                if !field.bounds.contains(localPoint) {
                    self.commit()
                }
                return event
            }
        }

        func removeOutsideInteractionMonitor() {
            if let outsideInteractionMonitor {
                NSEvent.removeMonitor(outsideInteractionMonitor)
                self.outsideInteractionMonitor = nil
            }
        }

        func commit() {
            guard !didResolve else { return }
            didResolve = true
            if let field {
                parent.text = field.stringValue
                field.window?.makeFirstResponder(nil)
            }
            removeOutsideInteractionMonitor()
            onCommit?()
        }

        func cancel() {
            guard !didResolve else { return }
            didResolve = true
            field?.window?.makeFirstResponder(nil)
            removeOutsideInteractionMonitor()
            onCancel?()
        }
    }
}

private final class WorkspaceSidebarRenameTextField: NSTextField {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
            case 36, 76:
                onCommit?()
            case 53:
                onCancel?()
            default:
                super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignFirstResponder() -> Bool {
        super.resignFirstResponder()
    }
}

struct WorkspaceSidebarWorkspaceSection: View {
    let workspace: WorkspaceSidebarWorkspaceViewModel
    let dragPreview: WorkspaceSidebarDropPreviewViewModel?
    let expansionProgress: CGFloat
    let emitsDropTarget: Bool

    @State private var isHovered = false
    @State private var hoveredWindowId: UInt32? = nil
    @State private var isEditingName = false
    @State private var editingNameDraft = ""
    @Namespace private var rowHoverNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let headerHeight: CGFloat = 26
    private let rowHeight: CGFloat = 23

    private var contentWidth: CGFloat { workspaceSidebarContentWidth(expansionProgress) }
    private var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress) }
    private var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    private var showsWindowRows: Bool { expansionProgress >= workspaceSidebarRowsRevealProgress }
    private var isDropTarget: Bool { dragPreview?.targetWorkspaceName == workspace.name }
    private var activeSidebarDragSourceWindowId: UInt32? { dragPreview?.sourceWindowId }
    private var sectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }

    var body: some View {
        interactiveSectionContent
            .padding(.vertical, isCompact ? 4 : 5)
            .padding(.horizontal, workspaceSidebarSectionInnerHorizontalInset)
            .frame(width: sectionWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .contextMenu {
                Button("Rename Workspace") {
                    beginInlineRename()
                }
                Button("Reset Workspace Name") {
                    resetWorkspaceNameFromSidebar(workspace)
                }
                Button(role: .destructive) {
                    deleteWorkspaceFromSidebar(workspace)
                } label: {
                    Text("Delete Workspace")
                }
            }
            .onHover { hover in
                isHovered = hover
                TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = nextWorkspaceSidebarHoveredWorkspaceName(
                    currentHoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
                    workspaceName: workspace.name,
                    isHovering: hover,
                )
            }
            .zIndex(isDropTarget ? 1 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: dragPreview)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: expansionProgress)
            .animation(reduceMotion ? workspaceSidebarReducedMotionHoverAnimation : workspaceSidebarHoverAnimation, value: isHovered)
            .animation(reduceMotion ? workspaceSidebarReducedMotionHoverAnimation : workspaceSidebarHoverAnimation, value: hoveredWindowId)
            .background {
                ZStack {
                    sectionBackground
                    if !isCompact {
                        sectionActivationButton
                    }
                }
            }
            .shadow(
                color: isDropTarget ? Color.accentColor.opacity(0.18) : .clear,
                radius: isDropTarget ? 12 : 0
            )
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: WorkspaceSidebarDropTargetPreferenceKey.self,
                        value: emitsDropTarget ? [WorkspaceSidebarDropTargetFrame(
                            kind: .workspace(workspace.name),
                            frame: geometry.frame(in: .named("workspaceSidebarContent")),
                        )] : [],
                    )
                }
            }
    }

    private func handleSectionClick() {
        if shouldHandleWorkspaceSidebarActivation(isEditing: isEditingName, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) {
            focusWorkspaceFromSidebar(workspace.name)
        }
    }

    private func beginInlineRename() {
        WorkspaceSidebarPanel.shared.beginInlineTextEditing()
        isEditingName = true
        editingNameDraft = workspace.displayName
    }

    private func commitInlineRename() {
        guard isEditingName else { return }
        let trimmed = editingNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingName = false
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
        guard !trimmed.isEmpty, trimmed != workspace.displayName else { return }
        renameWorkspaceFromSidebar(workspace, displayName: trimmed)
    }

    private func cancelInlineRename() {
        isEditingName = false
        editingNameDraft = ""
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
    }

    @ViewBuilder
    private var interactiveSectionContent: some View {
        if isCompact {
            Button(action: handleSectionClick) {
                sectionContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .contentShape(sectionShape)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(sectionShape)
        } else {
            sectionContent
                .contentShape(sectionShape)
        }
    }

    private var sectionActivationButton: some View {
        Button(action: handleSectionClick) {
            Color.clear
                .contentShape(sectionShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(workspace.displayName)
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Group {
                if isCompact {
                    header
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if isEditingName {
                    header
                } else {
                    headerButton
                }
            }
                .frame(height: headerHeight)
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
            windowRows
            dropPreviewRow
        }
    }

    private var headerButton: some View {
        Button(action: handleSectionClick) {
            header
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    beginInlineRename()
                },
        )
    }

    @ViewBuilder
    private var windowRows: some View {
        if showsWindowRows, !workspace.items.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(workspace.items) { item in
                    workspaceItemView(item)
                }
            }
            .padding(.leading, workspaceSidebarWindowRowsLeadingIndent)
        }
    }

    @ViewBuilder
    private func workspaceItemView(_ item: WorkspaceSidebarItemViewModel) -> some View {
        switch item.kind {
            case .window(let window):
                workspaceWindowButton(window, allowsDrag: true)
            case .tabGroup(let group):
                workspaceTabGroupView(group)
        }
    }

    @ViewBuilder
    private var dropPreviewRow: some View {
        if dragPreview?.targetWorkspaceName == workspace.name {
            WorkspaceSidebarPreviewRow(
                preview: dragPreview.orDie(),
                expansionProgress: expansionProgress,
                rowHeight: rowHeight,
                expandedContentWidth: contentWidth
            )
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
                removal: .identity,
            ))
        }
    }

    private func workspaceWindowButton(
        _ window: WorkspaceSidebarWindowViewModel,
        allowsDrag: Bool,
        subject: WindowDragSubject = .window,
        leadingHitInset: CGFloat = 0,
    ) -> some View {
        Button {
            guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
            focusWindowFromSidebar(window.windowId, fallbackWorkspace: window.workspaceName)
        } label: {
                WorkspaceSidebarWindowRow(
                    title: window.title ?? window.appName,
                    badge: nil,
                    isFocused: window.isFocused,
                    rowHeight: rowHeight,
                    isHovered: hoveredWindowId == window.windowId,
                    style: .window,
                    hoverNamespace: rowHoverNamespace,
                )
            .padding(.leading, leadingHitInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(WorkspaceSidebarOptionalDragModifier(
            isEnabled: allowsDrag,
            onChanged: {
                updateSidebarWindowDrag(window.windowId, subject: subject)
            },
            onEnded: {
                finishSidebarWindowDrag()
            },
        ))
        .onHover { hover in
            hoveredWindowId = nextWorkspaceSidebarHoveredWindowId(
                currentHoveredWindowId: hoveredWindowId,
                windowId: window.windowId,
                isHovering: hover,
            )
        }
        .opacity(activeSidebarDragSourceWindowId == window.windowId ? 0.25 : 1)
        .scaleEffect(activeSidebarDragSourceWindowId == window.windowId ? 0.94 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: activeSidebarDragSourceWindowId == window.windowId)
    }

    private func workspaceTabGroupView(_ group: WorkspaceSidebarTabGroupViewModel) -> some View {
        let isDragging = activeSidebarDragSourceWindowId == group.representativeWindowId
        let groupHoverId = UInt32.max - group.representativeWindowId
        return VStack(alignment: .leading, spacing: 1) {
            Button {
                guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
                focusWindowFromSidebar(group.representativeWindowId, fallbackWorkspace: group.workspaceName)
            } label: {
                WorkspaceSidebarWindowRow(
                    title: group.title.isEmpty ? "Tab Group" : group.title,
                    badge: group.windowCount > 1 ? "\(group.windowCount)" : nil,
                    isFocused: group.isFocused,
                    rowHeight: rowHeight,
                    isHovered: hoveredWindowId == groupHoverId,
                    style: .tabGroupHeader,
                    hoverNamespace: rowHoverNamespace,
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(WorkspaceSidebarOptionalDragModifier(
                isEnabled: true,
                onChanged: {
                    updateSidebarWindowDrag(group.representativeWindowId, subject: .group)
                },
                onEnded: {
                    finishSidebarWindowDrag()
                },
            ))
            .onHover { hover in
                hoveredWindowId = nextWorkspaceSidebarHoveredWindowId(
                    currentHoveredWindowId: hoveredWindowId,
                    windowId: groupHoverId,
                    isHovering: hover,
                )
            }
            .opacity(isDragging ? 0.25 : 1)
            .scaleEffect(isDragging ? 0.94 : 1)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(group.tabs) { tab in
                    workspaceWindowButton(tab, allowsDrag: true, subject: .window, leadingHitInset: 14)
                }
            }
            .opacity(isDragging ? 0.4 : 1)
        }
        .padding(.vertical, 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: isDragging)
    }

    // MARK: - Section Background

    private var sectionBackground: some View {
        sectionShape
            .fill(sectionBackgroundFill)
            .overlay {
                sectionShape
                    .strokeBorder(sectionBorderColor, lineWidth: sectionBorderWidth)
            }
    }

    // MARK: - Header

    private var header: some View {
        Group {
            if isEditingName && !isCompact {
                workspaceRenameEditor
            } else if isCompact {
                workspaceBadge
                    .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace.displayName)
                        .font(.system(size: 14, weight: workspace.isFocused ? .bold : .semibold))
                        .foregroundStyle(workspace.isFocused ? Color.white.opacity(0.96) : Color.white.opacity(0.86))
                        .lineLimit(1)
                    if let monitorName = workspace.monitorName, showsWindowRows {
                        Text(monitorName)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.48))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, workspaceSidebarHeaderLeadingPadding)
                .padding(.trailing, workspaceSidebarRowHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var workspaceRenameEditor: some View {
        WorkspaceSidebarProjectRenameField(
            text: $editingNameDraft,
            focusId: "workspace:\(workspace.name)",
            alignment: .left,
            fontSize: 14,
            fontWeight: .semibold,
            onCommit: commitInlineRename,
            onCancel: cancelInlineRename,
        )
            .padding(.horizontal, 5)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(workspaceSidebarActiveWorkspaceTint.opacity(0.48), lineWidth: 0.6)
                    }
            )
            .padding(.leading, workspaceSidebarHeaderLeadingPadding)
            .padding(.trailing, workspaceSidebarRowHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionBackgroundFill: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.13)
        } else if workspace.isFocused {
            return workspaceSidebarActiveWorkspaceTint.opacity(isCompact ? 0.32 : 0.17)
        } else if isCompact {
            if isHovered {
                return Color.white.opacity(0.06)
            }
        } else if isHovered {
            return Color.white.opacity(0.045)
        } else if workspace.isVisible && expansionProgress > 0.5 {
            return Color.white.opacity(0.02)
        }
        return Color.clear
    }

    private var sectionBorderColor: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.46)
        }
        if workspace.isFocused {
            return workspaceSidebarActiveWorkspaceTint.opacity(isCompact ? 0.70 : 0.42)
        }
        if isHovered || workspace.isVisible {
            return mattePanelSeparator.opacity(isCompact ? 0.32 : 0.24)
        }
        return Color.clear
    }

    private var sectionBorderWidth: CGFloat {
        if isDropTarget {
            return 1.5
        }
        if workspace.isFocused {
            return isCompact ? 0.9 : 0.7
        }
        if isHovered || workspace.isVisible {
            return 0.6
        }
        return 0.5
    }

    private var workspaceBadge: some View {
        Text(workspaceBadgeText)
            .font(.custom("Arial", size: isCompact ? 12 : 15).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(workspaceBadgeForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth, alignment: .center)
    }

    private var workspaceBadgeText: String {
        if workspace.isGeneratedName, workspace.sidebarLabel.isEmpty {
            return generatedWorkspaceBadgeText
        }
        if workspace.isGeneratedName, let initial = workspace.displayName.first {
            return String(initial).uppercased()
        }
        return workspace.displayName.first.map { String($0).uppercased() } ?? "W"
    }

    private var generatedWorkspaceBadgeText: String {
        let prefix = "Workspace "
        if workspace.displayName.hasPrefix(prefix) {
            let suffix = String(workspace.displayName.dropFirst(prefix.count))
            if !suffix.isEmpty {
                return suffix
            }
        }
        return workspace.displayName.first.map { String($0).uppercased() } ?? "W"
    }

    private var workspaceBadgeForeground: Color {
        if workspace.isFocused {
            return isCompact ? Color.white.opacity(0.92) : Color.white.opacity(0.90)
        }
        return Color.white.opacity(isCompact ? 0.72 : 0.54)
    }
}

// MARK: - Create Workspace Section

struct WorkspaceSidebarCreateWorkspaceSection: View {
    let dragPreview: WorkspaceSidebarDropPreviewViewModel?
    let expansionProgress: CGFloat
    let emitsDropTarget: Bool
    let onCreateWorkspace: () -> Void

    @State private var isHovered = false
    private var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress) }
    private var contentWidth: CGFloat { workspaceSidebarContentWidth(expansionProgress) }
    private var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    private var isDropTarget: Bool { dragPreview?.targetsNewWorkspace == true }
    private var sectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
                onCreateWorkspace()
            } label: {
                Group {
                    if isCompact {
                        plusBadge
                            .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)
                    } else {
                        HStack(spacing: workspaceSidebarHeaderSpacing) {
                            plusBadge
                            Text("New Workspace")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.66))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, workspaceSidebarSectionInnerHorizontalInset)
                .frame(width: sectionWidth, alignment: isCompact ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                .background(
                    sectionShape
                        .fill(createSectionFill)
                        .overlay {
                            sectionShape
                                .strokeBorder(
                                    isDropTarget ? Color.accentColor.opacity(0.46) : Color.white.opacity(isHovered ? 0.06 : 0),
                                    lineWidth: isDropTarget ? 1.5 : 0.5
                                )
                        }
                )
                .contentShape(sectionShape)
                }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
            .contentShape(sectionShape)
            .onHover { hover in
                isHovered = hover
            }
            if dragPreview?.targetsNewWorkspace == true {
                WorkspaceSidebarPreviewRow(
                    preview: dragPreview.orDie(),
                    expansionProgress: expansionProgress,
                    rowHeight: 22,
                    expandedContentWidth: contentWidth
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
                    removal: .opacity,
                ))
            }
        }
        .frame(width: sectionWidth, alignment: isCompact ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
        .clipped()
        .zIndex(isDropTarget ? 1 : 0)
        .shadow(
            color: isDropTarget ? Color.accentColor.opacity(0.18) : .clear,
            radius: isDropTarget ? 12 : 0
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.84), value: dragPreview)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: WorkspaceSidebarDropTargetPreferenceKey.self,
                    value: emitsDropTarget ? [WorkspaceSidebarDropTargetFrame(
                        kind: .newWorkspace,
                        frame: geometry.frame(in: .named("workspaceSidebarContent")),
                    )] : [],
                )
            }
        }
    }

    private var createSectionFill: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.13)
        }
        if isHovered {
            return Color.white.opacity(isCompact ? 0.08 : 0.06)
        }
        return Color.clear
    }

    private var plusBadge: some View {
        Image(systemName: "plus")
            .font(.system(size: isCompact ? 10 : 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(isHovered || isDropTarget ? 0.80 : 0.58))
            .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth, alignment: .center)
    }
}

// MARK: - Window Row

struct WorkspaceSidebarWindowRow: View {
    enum Style {
        case window
        case tabGroupHeader
    }

    let title: String
    let badge: String?
    let isFocused: Bool
    let rowHeight: CGFloat
    let isHovered: Bool
    let style: Style
    let hoverNamespace: Namespace.ID

    private var isTabGroupHeader: Bool { style == .tabGroupHeader }
    private var isActiveRow: Bool { isFocused }
    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: isTabGroupHeader ? 12.5 : 12, weight: isActiveRow ? .semibold : .regular))
                .foregroundStyle(rowTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isTabGroupHeader ? Color.white.opacity(0.64) : Color.white.opacity(0.52))
            }
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, 1.5)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            rowShape
                .fill(rowBackgroundFill)
            if isHovered {
                rowShape
                    .fill(rowHoverOverlayFill)
                    .matchedGeometryEffect(id: "workspace-sidebar-row-hover", in: hoverNamespace)
            }
        }
        .overlay {
            if isActiveRow {
                rowShape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.035),
                                Color.white.opacity(0.00),
                            ],
                            startPoint: .top,
                            endPoint: .bottom,
                        )
                    )
            }
        }
        .overlay {
            if isActiveRow {
                rowShape
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
            }
        }
        .contentShape(Rectangle())
    }

    private var rowTextColor: Color {
        if isActiveRow {
            return Color.white.opacity(isTabGroupHeader ? 0.96 : 1)
        }
        return Color.white.opacity(0.78)
    }

    private var rowBackgroundFill: Color {
        if isActiveRow {
            if isTabGroupHeader {
                return Color.white.opacity(0.14)
            }
            return Color.white.opacity(0.085)
        }
        return Color.clear
    }

    private var rowHoverOverlayFill: Color {
        isTabGroupHeader ? Color.white.opacity(0.04) : Color.white.opacity(0.045)
    }
}

// MARK: - Drop Preview Row

struct WorkspaceSidebarPreviewRow: View {
    let preview: WorkspaceSidebarDropPreviewViewModel
    let expansionProgress: CGFloat
    let rowHeight: CGFloat
    let expandedContentWidth: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.20))
                Image(systemName: preview.isTabGroup ? "square.stack.3d.up.fill" : "macwindow")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.92))
            }
            .frame(width: 18, height: 18)
            .opacity(0.92)

            Text(preview.label)
                .font(.system(size: 11.2, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(1)
                .opacity(max(expansionProgress, 0.12))
            Spacer(minLength: 0)
            if preview.isTabGroup, preview.windowCount > 1, expansionProgress > 0.72 {
                Text("\(preview.windowCount)")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.09))
                    )
            }
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, 1.5)
        .frame(height: rowHeight + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.105))
                .overlay {
                    RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                        .strokeBorder(
                            Color.accentColor.opacity(0.32),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                        )
                }
        )
        .shadow(color: Color.accentColor.opacity(0.12), radius: 9, y: 2)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }
}

// MARK: - Drag Modifier

private struct WorkspaceSidebarOptionalDragModifier: ViewModifier {
    let isEnabled: Bool
    let onChanged: () -> Void
    let onEnded: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.highPriorityGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in onChanged() }
                    .onEnded { _ in onEnded() },
            )
        } else {
            content
        }
    }
}
