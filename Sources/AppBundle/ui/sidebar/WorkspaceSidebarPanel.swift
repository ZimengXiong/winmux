import AppKit
import Common
import CoreGraphics
import SwiftUI

let workspaceSidebarPanelId = "WinMux.workspaceSidebar"
let workspaceSidebarContentLeadingInset: CGFloat = 12
let workspaceSidebarContentTrailingInset: CGFloat = 12
let workspaceSidebarCompactRailHorizontalInset: CGFloat = 7
let workspaceSidebarSectionInnerHorizontalInset: CGFloat = 5
let workspaceSidebarSectionGap: CGFloat = 5
let workspaceSidebarBadgeWidth: CGFloat = 22
let workspaceSidebarHeaderSpacing: CGFloat = 10
let workspaceSidebarHeaderRowLeadingPadding: CGFloat = 6
let workspaceSidebarRowsRevealProgress: CGFloat = 0.58
let workspaceSidebarPanelRightCornerRadius: CGFloat = RadiusToken.panel
let workspaceSidebarPlateCornerRadius: CGFloat = RadiusToken.section
let workspaceSidebarSectionCornerRadius: CGFloat = workspaceSidebarPlateCornerRadius
let workspaceSidebarRowCornerRadius: CGFloat = RadiusToken.row
let workspaceSidebarRowHorizontalPadding: CGFloat = 4
let workspaceSidebarWindowRowsLeadingIndent: CGFloat = 8
let workspaceSidebarAppIconSize: CGFloat = 14
let workspaceSidebarAppIconTextSpacing: CGFloat = 6
let workspaceSidebarTabGroupChildLeadingIndent: CGFloat = workspaceSidebarAppIconSize + workspaceSidebarAppIconTextSpacing - 2
let workspaceSidebarControlHeight: CGFloat = 30
let workspaceSidebarDropdownHeight: CGFloat = 28
let workspaceSidebarSearchHeight: CGFloat = 28
let workspaceSidebarDropdownCornerRadius: CGFloat = RadiusToken.card
let workspaceSidebarDropdownPadding: CGFloat = 7
let workspaceSidebarDropdownLabelSize: CGFloat = 11.5
let workspaceSidebarDropdownSymbolSize: CGFloat = 10.5
let workspaceSidebarPagerHeight: CGFloat = 32
let workspaceSidebarWorkspaceSectionHeaderHeight: CGFloat = 32
let workspaceSidebarWorkspaceRowHeight: CGFloat = 24
let workspaceSidebarWorkspaceSectionHeightCompact: CGFloat = 32
let workspaceSidebarWorkspaceSectionHeightExpanded: CGFloat = 32
let workspaceSidebarInUseOverrideEmptySectionMinHeight: CGFloat = 76
let workspaceSidebarProjectDotFrameHeight: CGFloat = 32
let workspaceSidebarMenuRowHeight: CGFloat = 28
let workspaceSidebarMenuRowSpacing: CGFloat = 3
let workspaceSidebarMenuRowHorizontalPadding: CGFloat = 10
let workspaceSidebarHoverAnimation: Animation = MotionToken.hover
let workspaceSidebarReducedMotionHoverAnimation: Animation = MotionToken.quick
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
    WorkspaceSidebarProjectColorPreset(name: "Blue", hex: "#7BA3C9"),
    WorkspaceSidebarProjectColorPreset(name: "Cyan", hex: "#6FBAB4"),
    WorkspaceSidebarProjectColorPreset(name: "Green", hex: "#7DBF8E"),
    WorkspaceSidebarProjectColorPreset(name: "Yellow", hex: "#C9B97A"),
    WorkspaceSidebarProjectColorPreset(name: "Orange", hex: "#C4956E"),
    WorkspaceSidebarProjectColorPreset(name: "Red", hex: "#C48181"),
    WorkspaceSidebarProjectColorPreset(name: "Pink", hex: "#BF8AAE"),
    WorkspaceSidebarProjectColorPreset(name: "Violet", hex: "#9B8FC4"),
]
extension WorkspaceSidebarPanel {
    func animateVisibleSidebarWidth(_ width: CGFloat, animation: Animation) {
        debugWorkspaceSidebarHoverLog("animateWidth panel=\(monitorScopeId) from=\(viewModel.workspaceSidebarVisibleWidth) to=\(width) frame=\(frame) mouse=\(NSEvent.mouseLocation) ignores=\(ignoresMouseEvents) expanded=\(viewModel.isWorkspaceSidebarExpanded)")
        withAnimation(animation) {
            viewModel.workspaceSidebarVisibleWidth = width
        }
        updateMousePassthrough()
        // The hover region just changed size under a possibly stationary cursor.
        scheduleHoverRecheckSoon()
    }

    func expandSidebar(to expandedWidth: CGFloat) {
        debugWorkspaceSidebarHoverLog("expandSidebar panel=\(monitorScopeId) target=\(expandedWidth) visible=\(viewModel.workspaceSidebarVisibleWidth) frame=\(frame) mouse=\(NSEvent.mouseLocation)")
        pendingExpand?.cancel()
        pendingExpand = nil
        NotificationCenter.default.post(name: workspaceSidebarWillExpandNotification, object: self)
        viewModel.isWorkspaceSidebarExpanded = true
        if !isVisible {
            refresh()
        }
        guard viewModel.workspaceSidebarVisibleWidth != expandedWidth else {
            updateMousePassthrough()
            return
        }
        animateVisibleSidebarWidth(expandedWidth, animation: .easeInOut(duration: animationDuration))
    }

    func cancelExpansionWork() {
        debugWorkspaceSidebarHoverLog("cancelExpansionWork panel=\(monitorScopeId) pendingExpand=\(pendingExpand != nil) pendingCollapse=\(pendingCollapse != nil) pendingFinalize=\(pendingCollapseFinalize != nil)")
        pendingExpand?.cancel()
        pendingExpand = nil
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
    }
}
extension WorkspaceSidebarPanel {
    func updateDropTargets(_ targets: [WorkspaceSidebarDropTargetFrame]) {
        workspaceSidebarDropTargets = convertDropTargets(targets)
    }

    func convertDropTargets(_ targets: [WorkspaceSidebarDropTargetFrame]) -> [WorkspaceSidebarDropTarget] {
        targets.compactMap { target in
            let windowRect = hostingView.convert(target.frame, to: nil)
            let screenRect = convertToScreen(windowRect)
            return WorkspaceSidebarDropTarget(kind: target.kind, rect: screenRect.monitorFrameNormalized())
        }
    }

    func visibleScreenRectNormalized() -> Rect? {
        guard isVisible, viewModel.workspaceSidebarVisibleWidth > 0 else { return nil }
        return CGRect(
            x: frame.minX,
            y: frame.minY,
            width: min(viewModel.workspaceSidebarVisibleWidth, frame.width),
            height: frame.height,
        ).monitorFrameNormalized()
    }
}
extension WorkspaceSidebarPanel {
    static func suppressEdgeTrapForWorkspaceActivation(duration: TimeInterval = 0.75) {
        let until = ProcessInfo.processInfo.systemUptime + duration
        for panel in visiblePanels {
            debugWorkspaceSidebarEdgeTrapLog("suppress panel=\(panel.monitorScopeId) until=\(until) sample=\(MousePointerTracker.shared.currentSample)")
            panel.edgeTrapStartedAt = nil
            panel.edgeTrapSuppressedUntil = max(panel.edgeTrapSuppressedUntil, until)
            panel.lastEdgeTrapSample = MousePointerTracker.shared.currentSample
        }
    }

    static func trapCursorForVisiblePanelsIfNeeded() {
        for panel in visiblePanels {
            panel.trapCursorForLeftEdgeSidebarActivationIfNeeded()
        }
    }

    func trapCursorForLeftEdgeSidebarActivationIfNeeded() {
        let sample = MousePointerTracker.shared.currentSample
        let collapsedWidth = workspaceSidebarRestingWidth(config.workspaceSidebar)
        debugWorkspaceSidebarEdgeTrapLog(
            "entry panel=\(monitorScopeId) visible=\(isVisible) enabled=\(config.workspaceSidebar.enabled) shift=\(currentSessionModifierFlags().contains(.maskShift)) mouseDrag=\(isMouseWindowDragInProgress()) sidebarDrag=\(isWorkspaceSidebarItemDragActive()) width=\(viewModel.workspaceSidebarVisibleWidth) collapsed=\(collapsedWidth) sample=\(sample) previous=\(String(describing: lastEdgeTrapSample)) suppressUntil=\(edgeTrapSuppressedUntil) startedAt=\(String(describing: edgeTrapStartedAt))"
        )
        guard isVisible,
              config.workspaceSidebar.enabled,
              workspaceSidebarAllowsLeftEdgeTrap(config.workspaceSidebar),
              !currentSessionModifierFlags().contains(.maskShift),
              !isMouseWindowDragInProgress(),
              !isWorkspaceSidebarItemDragActive(),
              viewModel.workspaceSidebarVisibleWidth <= collapsedWidth + 0.5
        else {
            debugWorkspaceSidebarEdgeTrapLog("skipPreconditions panel=\(monitorScopeId)")
            edgeTrapStartedAt = nil
            lastEdgeTrapSample = sample
            return
        }

        defer { lastEdgeTrapSample = sample }
        let previous = lastEdgeTrapSample
        guard sample.timestamp >= edgeTrapSuppressedUntil,
              let layoutMonitor = sortedMonitors.first(where: { workspaceSidebarMonitorScopeId(for: $0) == monitorScopeId })
        else {
            debugWorkspaceSidebarEdgeTrapLog("skipSuppressedOrNoMonitor panel=\(monitorScopeId) sampleTime=\(sample.timestamp) suppressUntil=\(edgeTrapSuppressedUntil)")
            edgeTrapStartedAt = nil
            return
        }
        let hasLeftMonitor = hasMonitorImmediatelyLeft(of: layoutMonitor)
        let crossesTrapRegion = crossesLeftEdgeTrapRegion(point: sample.point, previous: previous?.point, of: layoutMonitor)
        guard hasLeftMonitor, crossesTrapRegion else {
            debugWorkspaceSidebarEdgeTrapLog("skipRegion panel=\(monitorScopeId) hasLeftMonitor=\(hasLeftMonitor) crosses=\(crossesTrapRegion) monitorFrame=\(layoutMonitor.rect) samplePoint=\(sample.point) previousPoint=\(String(describing: previous?.point))")
            edgeTrapStartedAt = nil
            return
        }

        let deltaX = previous.map { sample.point.x - $0.point.x } ?? 0
        let isLeftwardFlick = deltaX <= -edgeTrapReleaseVelocityThreshold
        let isContinuingTrap = edgeTrapStartedAt != nil && sample.point.x <= layoutMonitor.rect.minX + edgeTrapBandWidth
        let shouldTrap = isContinuingTrap || isLeftwardFlick || isMouseWindowDragInProgress()
        guard shouldTrap else {
            debugWorkspaceSidebarEdgeTrapLog("skipVelocity panel=\(monitorScopeId) deltaX=\(deltaX) isLeftwardFlick=\(isLeftwardFlick) isContinuingTrap=\(isContinuingTrap)")
            edgeTrapStartedAt = nil
            return
        }

        let startedAt = edgeTrapStartedAt ?? sample.timestamp
        edgeTrapStartedAt = startedAt
        guard sample.timestamp - startedAt < edgeTrapReleaseDelay else {
            debugWorkspaceSidebarEdgeTrapLog("release panel=\(monitorScopeId) elapsed=\(sample.timestamp - startedAt) grace=\(edgeTrapCrossingGrace)")
            edgeTrapStartedAt = nil
            edgeTrapSuppressedUntil = sample.timestamp + edgeTrapCrossingGrace
            return
        }

        let trappedPoint = CGPoint(
            x: layoutMonitor.rect.minX + 1,
            y: sample.point.y.coerce(in: layoutMonitor.rect.minY ... max(layoutMonitor.rect.minY, layoutMonitor.rect.maxY - 1))
        )
        debugWorkspaceSidebarEdgeTrapLog("warp panel=\(monitorScopeId) from=\(sample.point) to=\(trappedPoint) deltaX=\(deltaX) isLeftwardFlick=\(isLeftwardFlick) isContinuingTrap=\(isContinuingTrap) elapsed=\(sample.timestamp - startedAt) monitorFrame=\(layoutMonitor.rect)")
        CGWarpMouseCursorPosition(trappedPoint)
        MousePointerTracker.shared.note(point: trappedPoint, timestamp: sample.timestamp)
    }

    private func hasMonitorImmediatelyLeft(of monitor: Monitor) -> Bool {
        sortedMonitors.contains { other in
            other.rect.maxX == monitor.rect.minX &&
                other.rect.maxY > monitor.rect.minY &&
                other.rect.minY < monitor.rect.maxY
        }
    }

    private func isInsideVerticalSpan(_ point: CGPoint, of monitor: Monitor) -> Bool {
        point.y >= monitor.rect.minY && point.y < monitor.rect.maxY
    }

    private func crossesLeftEdgeTrapRegion(point: CGPoint, previous: CGPoint?, of monitor: Monitor) -> Bool {
        if isInsideVerticalSpan(point, of: monitor),
           point.x >= monitor.rect.minX - edgeTrapBandWidth,
           point.x <= monitor.rect.minX + edgeTrapBandWidth
        {
            return true
        }
        guard let previous else { return false }
        let crossedLeftEdge = previous.x >= monitor.rect.minX && point.x < monitor.rect.minX
        let crossedBackIntoMonitor = previous.x < monitor.rect.minX && point.x >= monitor.rect.minX
        let crossedTrapBand = previous.x > monitor.rect.minX + edgeTrapBandWidth &&
            point.x < monitor.rect.minX - edgeTrapBandWidth
        guard crossedLeftEdge || crossedBackIntoMonitor || crossedTrapBand else { return false }
        return segmentIntersectsVerticalSpan(from: previous, to: point, of: monitor)
    }

    private func segmentIntersectsVerticalSpan(from start: CGPoint, to end: CGPoint, of monitor: Monitor) -> Bool {
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)
        return maxY >= monitor.rect.minY && minY < monitor.rect.maxY
    }
}
enum WorkspaceSidebarInlineTextKey {
    case text(String)
    case deleteBackward
    case deleteForward
    case deleteWordBackward
    case deleteToBeginningOfLine
    case moveUp
    case moveDown
    case commit
    case cancel
    case ignored
}

private let workspaceSidebarInlineTextEventTapCallback: CGEventTapCallBack = { _, type, event, _ in
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    let key = workspaceSidebarInlineTextKey(from: event)
    if case .ignored = key {
        return Unmanaged.passUnretained(event)
    }
    DispatchQueue.main.async {
        _ = WorkspaceSidebarPanel.activeInlineTextEditingPanel?.handleInlineTextEditingKey(key)
    }
    return nil
}

private func workspaceSidebarInlineTextKey(from event: CGEvent) -> WorkspaceSidebarInlineTextKey {
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let usesCommand = flags.contains(.maskCommand)
    let usesOption = flags.contains(.maskAlternate)
    let usesControl = flags.contains(.maskControl)
    switch keyCode {
        case 36, 76:
            return .commit
        case 53:
            return .cancel
        case 51:
            if usesCommand {
                return .deleteToBeginningOfLine
            }
            if usesOption {
                return .deleteWordBackward
            }
            return .deleteBackward
        case 117:
            return .deleteForward
        case 126:
            return .moveUp
        case 125:
            return .moveDown
        default:
            break
    }

    guard !usesCommand, !usesOption, !usesControl else {
        return .ignored
    }

    var length = 0
    var chars = [UniChar](repeating: 0, count: 8)
    event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
    guard length > 0 else { return .ignored }
    let text = String(utf16CodeUnits: chars, count: length)
    guard !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
        return .ignored
    }
    return text.isEmpty ? .ignored : .text(text)
}

extension WorkspaceSidebarPanel {
    func inlineTextKey(from event: NSEvent) -> WorkspaceSidebarInlineTextKey {
        let usesCommand = event.modifierFlags.contains(.command)
        let usesOption = event.modifierFlags.contains(.option)
        let usesControl = event.modifierFlags.contains(.control)
        switch event.keyCode {
            case 36, 76:
                return .commit
            case 53:
                return .cancel
            case 51:
                if usesCommand {
                    return .deleteToBeginningOfLine
                }
                if usesOption {
                    return .deleteWordBackward
                }
                return .deleteBackward
            case 117:
                return .deleteForward
            case 126:
                return .moveUp
            case 125:
                return .moveDown
            default:
                break
        }

        guard !usesCommand, !usesOption, !usesControl,
              let text = event.characters,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            return .ignored
        }
        return text.isEmpty ? .ignored : .text(text)
    }

    func beginInlineTextEditing(
        locksExpansion: Bool = true,
        cancelsOnPointerExit: Bool = true,
        onCancel: (@MainActor () -> Void)? = nil,
        onKeyDown: (@MainActor (WorkspaceSidebarInlineTextKey) -> Void)? = nil
    ) {
        debugWorkspaceSidebarRenameLog("beginInlineTextEditing isKeyBefore=\(isKeyWindow) firstResponder=\(String(describing: firstResponder)) mouseInside=\(isMouseInsideVisibleRegion())")
        inlineTextEditingActive = true
        inlineTextEditingLocksExpansion = locksExpansion
        inlineTextEditingCancelsOnPointerExit = cancelsOnPointerExit
        WorkspaceSidebarPanel.activeInlineTextEditingPanel = self
        inlineTextEditingCancel = onCancel
        inlineTextEditingKeyDown = onKeyDown
        inlineTextEditingStartedAt = .now
        inlineTextEditingPointerEnteredVisibleRegion = isMouseInsideVisibleRegion()
        prepareForInlineTextEditing()
        installInlineTextEditingEventMonitors()
        installInlineTextEditingKeyEventTap()
    }

    func endInlineTextEditing() {
        guard inlineTextEditingActive else { return }
        debugWorkspaceSidebarRenameLog("endInlineTextEditing isKey=\(isKeyWindow) firstResponder=\(String(describing: firstResponder))")
        inlineTextEditingActive = false
        inlineTextEditingLocksExpansion = true
        inlineTextEditingCancelsOnPointerExit = true
        if WorkspaceSidebarPanel.activeInlineTextEditingPanel === self {
            WorkspaceSidebarPanel.activeInlineTextEditingPanel = nil
        }
        inlineTextEditingCancel = nil
        inlineTextEditingKeyDown = nil
        inlineTextEditingPointerEnteredVisibleRegion = false
        removeInlineTextEditingEventMonitors()
        removeInlineTextEditingKeyEventTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.updateHoverStateFromMousePosition()
        }
    }

    func prepareForInlineTextEditing() {
        debugWorkspaceSidebarRenameLog("prepareForInlineTextEditing before visible=\(isVisible) isKey=\(isKeyWindow) ignoresMouse=\(ignoresMouseEvents) firstResponder=\(String(describing: firstResponder))")
        cancelExpansionWork()
        expandSidebar(to: CGFloat(config.workspaceSidebar.width))
        ignoresMouseEvents = false
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        makeKey()
        NSApp.activate(ignoringOtherApps: true)
        debugWorkspaceSidebarRenameLog("prepareForInlineTextEditing after visible=\(isVisible) isKey=\(isKeyWindow) ignoresMouse=\(ignoresMouseEvents) firstResponder=\(String(describing: firstResponder)) activeApp=\(NSApp.isActive)")
    }

    func cancelInlineTextEditing() {
        guard inlineTextEditingActive else { return }
        debugWorkspaceSidebarRenameLog("cancelInlineTextEditing isKey=\(isKeyWindow) firstResponder=\(String(describing: firstResponder))")
        inlineTextEditingCancel?()
    }

    func handleInlineTextEditingKey(_ key: WorkspaceSidebarInlineTextKey) -> Bool {
        guard inlineTextEditingActive, let inlineTextEditingKeyDown else { return false }
        debugWorkspaceSidebarRenameLog("handleInlineTextEditingKey key=\(key)")
        inlineTextEditingKeyDown(key)
        if case .ignored = key {
            return false
        }
        return true
    }

    func shouldCancelInlineTextEditingForOutsidePointer(isMouseDown: Bool) -> Bool {
        guard inlineTextEditingCancelsOnPointerExit else { return false }
        if isMouseInsideVisibleRegion() {
            inlineTextEditingPointerEnteredVisibleRegion = true
            return false
        }
        if inlineTextEditingPointerEnteredVisibleRegion {
            debugWorkspaceSidebarRenameLog("outsidePointerCancel afterEntered isMouseDown=\(isMouseDown)")
            return true
        }
        let shouldCancel = isMouseDown && Date().timeIntervalSince(inlineTextEditingStartedAt) > 0.25
        if shouldCancel {
            debugWorkspaceSidebarRenameLog("outsidePointerCancel clickGraceElapsed")
        }
        return shouldCancel
    }

    func installInlineTextEditingEventMonitors() {
        removeInlineTextEditingEventMonitors()
        let mouseDownMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let localMouseDown = NSEvent.addLocalMonitorForEvents(matching: mouseDownMask) { [weak self] event in
            guard let self else { return event }
            if !self.isEventInsideVisibleRegion(event),
               self.shouldCancelInlineTextEditingForOutsidePointer(isMouseDown: true)
            {
                Task { @MainActor in self.cancelInlineTextEditing() }
            }
            return event
        }
        let localMouseMove = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            guard let self else { return event }
            if self.shouldCancelInlineTextEditingForOutsidePointer(isMouseDown: false) {
                Task { @MainActor in self.cancelInlineTextEditing() }
            }
            return event
        }
        let globalMouseDown = NSEvent.addGlobalMonitorForEvents(matching: mouseDownMask) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if !self.isScreenPointInsideVisibleRegion(event.locationInWindow),
                   self.shouldCancelInlineTextEditingForOutsidePointer(isMouseDown: true)
                {
                    self.cancelInlineTextEditing()
                }
            }
        }
        let globalMouseMove = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.shouldCancelInlineTextEditingForOutsidePointer(isMouseDown: false) {
                    self.cancelInlineTextEditing()
                }
            }
        }
        inlineTextEditingEventMonitors = [localMouseDown, localMouseMove, globalMouseDown, globalMouseMove].compactMap { $0 }
    }

    func removeInlineTextEditingEventMonitors() {
        for monitor in inlineTextEditingEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        inlineTextEditingEventMonitors = []
    }

    func installInlineTextEditingKeyEventTap() {
        removeInlineTextEditingKeyEventTap()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: workspaceSidebarInlineTextEventTapCallback,
            userInfo: nil
        ) else {
            debugWorkspaceSidebarRenameLog("installKeyEventTap failed")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            debugWorkspaceSidebarRenameLog("installKeyEventTap source failed")
            return
        }
        inlineTextEditingKeyEventTap = tap
        inlineTextEditingKeyEventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        debugWorkspaceSidebarRenameLog("installKeyEventTap ok")
    }

    func removeInlineTextEditingKeyEventTap() {
        if let source = inlineTextEditingKeyEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = inlineTextEditingKeyEventTap {
            CFMachPortInvalidate(tap)
        }
        inlineTextEditingKeyEventTap = nil
        inlineTextEditingKeyEventTapRunLoopSource = nil
    }

    func isEventInsideVisibleRegion(_ event: NSEvent) -> Bool {
        guard event.window === self else { return false }
        let point = convertPoint(toScreen: event.locationInWindow)
        return isScreenPointInsideVisibleRegion(point)
    }

    func isScreenPointInsideVisibleRegion(_ point: CGPoint) -> Bool {
        guard isVisible else { return false }
        let visibleRegion = NSRect(
            x: frame.minX,
            y: frame.minY,
            width: viewModel.workspaceSidebarVisibleWidth,
            height: frame.height,
        )
        return visibleRegion.contains(point)
    }
}
struct WorkspaceSidebarPanelLayout {
    let frame: NSRect
    let expandedWidth: CGFloat
    let collapsedWidth: CGFloat
}

extension WorkspaceSidebarPanel {
    func currentSidebarPanelLayout() -> WorkspaceSidebarPanelLayout? {
        currentSidebarPanelLayout(on: workspaceSidebarResolvedPanelMonitor())
    }

    func currentSidebarPanelLayout(on monitor: Monitor) -> WorkspaceSidebarPanelLayout? {
        guard TrayMenuModel.shared.isEnabled,
              config.workspaceSidebar.enabled,
              let screen = workspaceSidebarPanelScreen(for: monitor)
        else { return nil }
        guard !shouldSuppressWorkspaceSidebarForFullscreenContent() else { return nil }

        let sidebarConfig = config.workspaceSidebar
        let expandedWidth = CGFloat(sidebarConfig.width)
        let maximumExpandedWidth = expandedWidth * 2
        let collapsedWidth = workspaceSidebarRestingWidth(sidebarConfig)
        guard expandedWidth > 0, collapsedWidth >= 0 else { return nil }

        let menuBarReserveHeight = min(CGFloat(sidebarConfig.menuBarReserveHeight), max(screen.frame.height - 1, 0))
        return WorkspaceSidebarPanelLayout(
            frame: NSRect(
                x: screen.frame.minX,
                y: screen.frame.minY,
                width: maximumExpandedWidth,
                height: screen.frame.height - menuBarReserveHeight,
            ),
            expandedWidth: expandedWidth,
            collapsedWidth: collapsedWidth,
        )
    }

    func workspaceSidebarPanelScreen() -> NSScreen? {
        workspaceSidebarPanelScreen(for: workspaceSidebarResolvedPanelMonitor())
    }

    func workspaceSidebarPanelScreen(for monitor: Monitor) -> NSScreen? {
        NSScreen.screens.getOrNil(
            atIndex: monitor.monitorAppKitNsScreenScreensId - 1
        ) ?? NSScreen.screens.first
    }
}
extension WorkspaceSidebarPanel {
    func setHovering(_ isHovering: Bool) {
        let expandedWidth = CGFloat(config.workspaceSidebar.width)
        let collapsedWidth = workspaceSidebarRestingWidth(config.workspaceSidebar)
        if viewModel.workspaceSidebarVisibleWidth > collapsedWidth + 0.5 || pendingCollapse != nil {
            debugWorkspaceSidebarHoverLog("setHovering panel=\(monitorScopeId) isHovering=\(isHovering) visible=\(viewModel.workspaceSidebarVisibleWidth) frame=\(frame) mouse=\(NSEvent.mouseLocation)")
        }
        if isHovering {
            handleHoverEnter(
                expandedWidth: max(expandedWidth, viewModel.workspaceSidebarVisibleWidth),
                collapsedWidth: collapsedWidth
            )
        } else {
            handleHoverExit(collapsedWidth: collapsedWidth)
        }
    }

    func shouldLockExpansionForSidebarDrag() -> Bool {
        shouldLockWorkspaceSidebarExpansion(
            hasDropPreview: TrayMenuModel.shared.workspaceSidebarDropPreview != nil,
            hasPinnedDraggedWindow: hasPinnedDraggedWindow(),
            isSidebarDragInProgress: getCurrentMouseManipulationKind() == .move && getCurrentMouseDragStartedInSidebar(),
            hasActiveEditor: isMenuTrackingOrInGracePeriod() || shouldKeepSidebarOpenForInlineTextEditing(),
        ) || isMouseWindowDragInProgress()
    }

    func shouldKeepSidebarOpenForInlineTextEditing() -> Bool {
        commandExpansionLocksCollapse || (inlineTextEditingActive && inlineTextEditingLocksExpansion)
    }
}
extension WorkspaceSidebarPanel {
    func showHoverCue(cueWidth: CGFloat, expandedWidth: CGFloat, collapsedWidth: CGFloat) {
        if !isVisible {
            refresh()
        }
        if viewModel.workspaceSidebarVisibleWidth < cueWidth {
            animateVisibleSidebarWidth(
                cueWidth,
                animation: .spring(response: hoverCueAnimationResponse, dampingFraction: 0.72),
            )
        } else {
            updateMousePassthrough()
        }

        guard isMouseDeepEnoughToExpand() else {
            pendingExpand?.cancel()
            pendingExpand = nil
            return
        }
        scheduleHoverExpansion(expandedWidth: expandedWidth, collapsedWidth: collapsedWidth)
    }

    func scheduleHoverExpansion(expandedWidth: CGFloat, collapsedWidth: CGFloat) {
        guard pendingExpand == nil else { return }
        let expand = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingExpand = nil
            guard self.isMouseInsideHoverRegion(),
                  self.isMouseDeepEnoughToExpand()
            else { return }
            self.expandSidebar(to: expandedWidth)
        }
        pendingExpand = expand
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverOpenDelay, execute: expand)
    }
}
extension WorkspaceSidebarPanel {
    func handleHoverEnter(expandedWidth: CGFloat, collapsedWidth: CGFloat) {
        let cueWidth = workspaceSidebarHoverCueWidth(collapsedWidth: collapsedWidth, expandedWidth: expandedWidth)
        let isExpansionLocked = shouldLockExpansionForSidebarDrag()
        let isExternalWindowDrag = isMouseWindowDragInProgress()
        let isSidebarOriginatedDrag = getCurrentMouseDragStartedInSidebar()
        let shouldSuppressDragExpansion = shouldSuppressWorkspaceSidebarHoverExpansionForDrag(
            isSidebarItemDragActive: isWorkspaceSidebarItemDragActive(),
            isSidebarOriginatedDrag: isSidebarOriginatedDrag,
        )
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
        if shouldSuppressDragExpansion {
            pendingExpand?.cancel()
            pendingExpand = nil
            updateMousePassthrough()
            return
        }

        if isExternalWindowDrag && !isSidebarOriginatedDrag && isMousePushedAgainstDisplayEdge() {
            showCollapsedSidebarDuringExternalDrag(
                collapsedWidth: workspaceSidebarHoverActivationWidth(config.workspaceSidebar)
            )
            return
        }
        if !shouldDelayWorkspaceSidebarExpansion(
            isExpanded: viewModel.isWorkspaceSidebarExpanded,
            isExpansionLocked: isExpansionLocked,
            isMouseWindowDragInProgress: isExternalWindowDrag,
        ) {
            expandSidebar(to: expandedWidth)
            return
        }
        showHoverCue(cueWidth: cueWidth, expandedWidth: expandedWidth, collapsedWidth: collapsedWidth)
    }

    func showCollapsedSidebarDuringExternalDrag(collapsedWidth: CGFloat) {
        pendingExpand?.cancel()
        pendingExpand = nil
        if !isVisible {
            refresh()
        }
        if viewModel.workspaceSidebarVisibleWidth != collapsedWidth {
            animateVisibleSidebarWidth(collapsedWidth, animation: .easeInOut(duration: animationDuration))
        } else {
            updateMousePassthrough()
        }
    }
}
extension WorkspaceSidebarPanel {
    func handleHoverExit(collapsedWidth: CGFloat) {
        debugWorkspaceSidebarHoverLog("handleHoverExit panel=\(monitorScopeId) visible=\(viewModel.workspaceSidebarVisibleWidth) collapsed=\(collapsedWidth) expanded=\(viewModel.isWorkspaceSidebarExpanded) suppressActive=\(Date() < splitBrowseCollapseSuppressedUntil) mouse=\(NSEvent.mouseLocation)")
        pendingExpand?.cancel()
        pendingExpand = nil
        guard !config.workspaceSidebar.alwaysExpanded else {
            cancelExpansionWork()
            expandSidebar(to: CGFloat(config.workspaceSidebar.width))
            return
        }
        guard Date() >= splitBrowseCollapseSuppressedUntil else {
            debugWorkspaceSidebarHoverLog("handleHoverExit suppressed panel=\(monitorScopeId)")
            return
        }
        guard !shouldLockExpansionForSidebarDrag() else {
            debugWorkspaceSidebarHoverLog("handleHoverExit locked panel=\(monitorScopeId)")
            return
        }
        let needsCollapse =
            viewModel.isWorkspaceSidebarExpanded ||
            viewModel.workspaceSidebarVisibleWidth != collapsedWidth
        guard needsCollapse, pendingCollapse == nil else {
            debugWorkspaceSidebarHoverLog("handleHoverExit noop panel=\(monitorScopeId) needsCollapse=\(needsCollapse) pendingCollapse=\(pendingCollapse != nil)")
            return
        }
        scheduleCollapse(collapsedWidth: collapsedWidth)
    }

    func scheduleCollapse(collapsedWidth: CGFloat) {
        guard !config.workspaceSidebar.alwaysExpanded else { return }
        debugWorkspaceSidebarHoverLog("scheduleCollapse panel=\(monitorScopeId) visible=\(viewModel.workspaceSidebarVisibleWidth) collapsed=\(collapsedWidth) mouse=\(NSEvent.mouseLocation)")
        NotificationCenter.default.post(name: workspaceSidebarWillCollapseNotification, object: self)
        let collapse = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCollapse = nil
            guard !config.workspaceSidebar.alwaysExpanded else { return }
            debugWorkspaceSidebarHoverLog("collapseFire panel=\(self.monitorScopeId) visible=\(self.viewModel.workspaceSidebarVisibleWidth) mouse=\(NSEvent.mouseLocation) suppressActive=\(Date() < self.splitBrowseCollapseSuppressedUntil)")
            guard Date() >= self.splitBrowseCollapseSuppressedUntil else {
                debugWorkspaceSidebarHoverLog("collapseFire suppressed panel=\(self.monitorScopeId)")
                return
            }
            let inside = self.isMouseInsideHoverRegion()
            let locked = self.shouldLockExpansionForSidebarDrag()
            guard !inside, !locked else {
                debugWorkspaceSidebarHoverLog("collapseFire cancelled panel=\(self.monitorScopeId) inside=\(inside) locked=\(locked)")
                return
            }
            self.animateVisibleSidebarWidth(collapsedWidth, animation: .easeInOut(duration: self.animationDuration))
            self.scheduleCollapseFinalize()
        }
        pendingCollapse = collapse
        let collapseDelay: TimeInterval = viewModel.isWorkspaceSidebarExpanded ? 0.08 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: collapse)
    }

    func scheduleCollapseFinalize() {
        let finalize = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCollapseFinalize = nil
            guard !config.workspaceSidebar.alwaysExpanded else { return }
            debugWorkspaceSidebarHoverLog("collapseFinalize panel=\(self.monitorScopeId) visible=\(self.viewModel.workspaceSidebarVisibleWidth) mouse=\(NSEvent.mouseLocation) suppressActive=\(Date() < self.splitBrowseCollapseSuppressedUntil)")
            guard Date() >= self.splitBrowseCollapseSuppressedUntil else { return }
            let inside = self.isMouseInsideHoverRegion()
            let locked = self.shouldLockExpansionForSidebarDrag()
            guard !inside, !locked else {
                debugWorkspaceSidebarHoverLog("collapseFinalize cancelled panel=\(self.monitorScopeId) inside=\(inside) locked=\(locked)")
                return
            }
            viewModel.isWorkspaceSidebarExpanded = false
            self.updateMousePassthrough()
        }
        pendingCollapseFinalize = finalize
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration, execute: finalize)
    }
}
extension WorkspaceSidebarPanel {
    func installMenuTrackingObservers() {
        let center = NotificationCenter.default
        menuTrackingObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.beginMenuTrackingIfNeeded() }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.endMenuTrackingIfNeeded() }
            },
        ]
    }

    func beginMenuTrackingIfNeeded() {
        guard isVisible,
              viewModel.workspaceSidebarVisibleWidth > 0,
              isMouseInsideVisibleRegion()
        else { return }
        menuTrackingDepth += 1
        menuTrackingGraceUntil = .distantFuture
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
        expandSidebar(to: CGFloat(config.workspaceSidebar.width))
    }

    func endMenuTrackingIfNeeded() {
        guard menuTrackingDepth > 0 else { return }
        menuTrackingDepth -= 1
        guard menuTrackingDepth == 0 else { return }
        menuTrackingGraceUntil = Date().addingTimeInterval(menuTrackingEndGrace)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.updateHoverStateFromMousePosition()
        }
        // The 0.08s recheck lands inside the grace period, whose expansion lock swallows a
        // hover exit. With a stationary cursor no pointer event re-evaluates after the grace
        // expires, so schedule one recheck just past it.
        DispatchQueue.main.asyncAfter(deadline: .now() + menuTrackingEndGrace + 0.05) { [weak self] in
            self?.updateHoverStateFromMousePosition()
        }
    }

    func isMenuTrackingOrInGracePeriod(now: Date = .now) -> Bool {
        menuTrackingDepth > 0 || now < menuTrackingGraceUntil
    }
}
extension WorkspaceSidebarPanel {
    /// Hover state is a pure function of the mouse position and the panel geometry, so it is
    /// driven by the global/local pointer-event monitors (mouse position changes) plus explicit
    /// rechecks at the points where the panel itself appears or resizes (geometry changes).
    /// This used to be a permanent CVDisplayLink subscription polling at 30Hz, which kept the
    /// display link running and woke the main actor every vsync even when the machine was idle.
    static func noteHoverPointerActivityForVisiblePanels(timestamp: TimeInterval) {
        for panel in visiblePanels {
            panel.noteHoverPointerActivity(timestamp: timestamp)
        }
    }

    /// For lock-release points that arrive without pointer movement (drag ends on mouse-up
    /// with a stationary cursor): the expansion locks cleared, so hover must be re-evaluated
    /// even though no pointer event will fire.
    static func scheduleHoverRecheckForVisiblePanels() {
        for panel in visiblePanels {
            panel.scheduleHoverRecheckSoon()
        }
    }

    /// Rate-limited to `hoverPollInterval`, with a trailing recheck so the final position of an
    /// event burst is always evaluated (a leading-edge-only throttle could drop the last event
    /// and leave hover state stale until the next mouse move).
    private func noteHoverPointerActivity(timestamp: TimeInterval) {
        if timestamp - lastHoverMonitorTimestamp >= hoverPollInterval {
            lastHoverMonitorTimestamp = timestamp
            updateHoverStateFromMousePosition()
        } else if !hasPendingHoverRecheck {
            hasPendingHoverRecheck = true
            let delay = max(hoverPollInterval - (timestamp - lastHoverMonitorTimestamp), 0.001)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.hasPendingHoverRecheck = false
                self.lastHoverMonitorTimestamp = ProcessInfo.processInfo.systemUptime
                self.updateHoverStateFromMousePosition()
            }
        }
    }

    /// Deferred (not inline) so hover reevaluation can be requested from inside
    /// expansion/collapse/refresh paths without re-entering them synchronously.
    func scheduleHoverRecheckSoon() {
        guard !hasPendingHoverRecheck else { return }
        hasPendingHoverRecheck = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasPendingHoverRecheck = false
            self.updateHoverStateFromMousePosition()
        }
    }

    func updateHoverStateFromMousePosition() {
        guard isVisible else { return }
        updateMousePassthrough()
        setHovering(isMouseInsideHoverRegion())
    }
}
extension WorkspaceSidebarPanel {
    func updateMousePassthrough() {
        let inside = isMouseInsideVisibleRegion()
        let shouldIgnoreMouseEvents = !inside
        if ignoresMouseEvents != shouldIgnoreMouseEvents {
            debugWorkspaceSidebarHoverLog("mousePassthrough panel=\(monitorScopeId) ignores \(ignoresMouseEvents)->\(shouldIgnoreMouseEvents) insideVisible=\(inside) visibleWidth=\(viewModel.workspaceSidebarVisibleWidth) frame=\(frame) mouse=\(NSEvent.mouseLocation)")
            ignoresMouseEvents = shouldIgnoreMouseEvents
        }
    }

    func isMouseInsideHoverRegion() -> Bool {
        guard isVisible else { return false }
        let hoverWidth = max(
            viewModel.workspaceSidebarVisibleWidth,
            workspaceSidebarHoverActivationWidth(config.workspaceSidebar),
        ) + hoverExitTolerance
        let hoverRegion = NSRect(x: frame.minX, y: frame.minY, width: hoverWidth, height: frame.height)
        let inside = hoverRegion.contains(NSEvent.mouseLocation)
        if viewModel.workspaceSidebarVisibleWidth > workspaceSidebarRestingWidth(config.workspaceSidebar) + 0.5 || pendingCollapse != nil {
            debugWorkspaceSidebarHoverLog("hoverRegion panel=\(monitorScopeId) inside=\(inside) hoverWidth=\(hoverWidth) visibleWidth=\(viewModel.workspaceSidebarVisibleWidth) frame=\(frame) mouse=\(NSEvent.mouseLocation) suppressUntil=\(splitBrowseCollapseSuppressedUntil)")
        }
        return inside
    }

    func isMouseInsideVisibleRegion() -> Bool {
        guard isVisible else { return false }
        let visibleRegion = NSRect(
            x: frame.minX,
            y: frame.minY,
            width: viewModel.workspaceSidebarVisibleWidth,
            height: frame.height,
        )
        return visibleRegion.contains(NSEvent.mouseLocation)
    }

    func isMouseDeepEnoughToExpand() -> Bool {
        guard isVisible else { return false }
        return isWorkspaceSidebarHoverDeepEnoughToExpand(
            mouseX: NSEvent.mouseLocation.x,
            sidebarMinX: frame.minX,
            collapsedWidth: workspaceSidebarHoverActivationWidth(config.workspaceSidebar),
        )
    }
}
extension WorkspaceSidebarPanel {
    func refresh() {
        refresh(on: workspaceSidebarResolvedPanelMonitor())
    }

    func refresh(on monitor: Monitor) {
        applyWorkspaceSidebarLayer(stayOnTop: config.workspaceSidebar.stayOnTop)
        guard let layout = currentSidebarPanelLayout(on: monitor) else {
            cancelExpansionWork()
            resetHiddenSidebarState()
            return
        }

        if frame != layout.frame {
            setFrame(layout.frame, display: true, animate: false)
        }
        if config.workspaceSidebar.alwaysExpanded {
            cancelExpansionWork()
            let targetWidth = workspaceSidebarPersistentVisibleWidth(
                currentWidth: viewModel.workspaceSidebarVisibleWidth,
                previousExpandedWidth: persistentExpansionWidth,
                expandedWidth: layout.expandedWidth,
            )
            persistentExpansionWidth = layout.expandedWidth
            viewModel.isWorkspaceSidebarExpanded = true
            if viewModel.workspaceSidebarVisibleWidth != targetWidth {
                viewModel.workspaceSidebarVisibleWidth = targetWidth
            }
        } else if persistentExpansionWidth != nil {
            cancelExpansionWork()
            persistentExpansionWidth = nil
            viewModel.isWorkspaceSidebarExpanded = false
            viewModel.workspaceSidebarVisibleWidth = layout.collapsedWidth
        } else if viewModel.workspaceSidebarVisibleWidth == 0 {
            viewModel.workspaceSidebarVisibleWidth = viewModel.isWorkspaceSidebarExpanded
                ? layout.expandedWidth
                : layout.collapsedWidth
        } else if !viewModel.isWorkspaceSidebarExpanded,
                  pendingExpand == nil,
                  pendingCollapse == nil,
                  viewModel.workspaceSidebarVisibleWidth != layout.collapsedWidth
        {
            // Apply auto-hide/collapsed-width changes immediately on config reload.
            viewModel.workspaceSidebarVisibleWidth = layout.collapsedWidth
        }
        updateMousePassthrough()
        orderFrontRegardless()
        // Panel geometry may have just changed under a stationary cursor; hover is otherwise
        // event-driven from the pointer monitors.
        scheduleHoverRecheckSoon()
    }

    func refreshForCurrentDragIfNeeded() {
        guard isMouseWindowDragInProgress() else { return }
        WorkspaceSidebarPanel.refreshAll()
    }

    func resetHiddenSidebarState() {
        // Runs for every inactive panel on every refreshAll — guard the shared-model writes so
        // they don't invalidate every observer each session.
        workspaceSidebarDropTargets = []
        setWorkspaceSidebarDropPreviewIfChanged(nil)
        TrayMenuModel.shared.setIfChanged(\.workspaceSidebarHoveredWorkspaceName, nil)
        viewModel.setIfChanged(\.workspaceSidebarVisibleWidth, 0)
        if isVisible {
            orderOut(nil)
        }
    }
}
