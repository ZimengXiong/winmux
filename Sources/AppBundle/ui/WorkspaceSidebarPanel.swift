import AppKit
import SwiftUI

private let workspaceSidebarPanelId = "AeroSpace.workspaceSidebar"
private let workspaceSidebarContentLeadingInset: CGFloat = 6
private let workspaceSidebarContentTrailingInset: CGFloat = 10
private let workspaceSidebarSectionInnerHorizontalInset: CGFloat = 4
private let workspaceSidebarBadgeWidth: CGFloat = 22
private let workspaceSidebarHeaderSpacing: CGFloat = 8
private let workspaceSidebarRowsRevealProgress: CGFloat = 0.58
private let workspaceSidebarSectionCornerRadius: CGFloat = 10
private let workspaceSidebarHoverCueWidthDelta: CGFloat = 12
private let workspaceSidebarHoverOpenThresholdFraction: CGFloat = 0.5
@MainActor
private var workspaceSidebarDropTargets: [WorkspaceSidebarDropTarget] = []

enum WorkspaceSidebarEditorEndEditingAction: Equatable {
    case commit
    case cancel
}

@MainActor
private func workspaceSidebarCompactSectionWidth() -> CGFloat {
    max(
        CGFloat(config.workspaceSidebar.collapsedWidth) -
            workspaceSidebarContentLeadingInset -
            workspaceSidebarContentTrailingInset,
        workspaceSidebarBadgeWidth + (workspaceSidebarSectionInnerHorizontalInset * 2) + 2,
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

enum WorkspaceSidebarDropTargetKind: Equatable {
    case workspace(String)
    case newWorkspace
}

struct WorkspaceSidebarDropTarget {
    let kind: WorkspaceSidebarDropTargetKind
    let rect: Rect
}

struct WorkspaceSidebarDropTargetFrame: Equatable {
    let kind: WorkspaceSidebarDropTargetKind
    let frame: CGRect
}

private struct WorkspaceSidebarRenameKeyEvent {
    let modifierFlags: NSEvent.ModifierFlags
    let characters: String?

    init(_ event: NSEvent) {
        modifierFlags = event.modifierFlags
        characters = event.characters
    }
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

struct WorkspaceSidebarBeginEditingPlan: Equatable {
    let workspaceToCommit: String?
    let nextEditingWorkspaceName: String
    let nextEditingText: String
}

func planWorkspaceSidebarBeginEditing(
    currentEditingWorkspaceName: String?,
    currentEditingText: String,
    targetWorkspaceName: String,
    targetInitialText: String?,
    targetPersistedLabel: String?,
) -> WorkspaceSidebarBeginEditingPlan {
    if currentEditingWorkspaceName == targetWorkspaceName {
        return WorkspaceSidebarBeginEditingPlan(
            workspaceToCommit: nil,
            nextEditingWorkspaceName: targetWorkspaceName,
            nextEditingText: currentEditingText,
        )
    }
    return WorkspaceSidebarBeginEditingPlan(
        workspaceToCommit: currentEditingWorkspaceName,
        nextEditingWorkspaceName: targetWorkspaceName,
        nextEditingText: targetInitialText ?? targetPersistedLabel ?? "",
    )
}

func nextWorkspaceSidebarEditingText(
    currentEditingWorkspaceName: String?,
    fieldWorkspaceName: String,
    currentEditingText: String,
    newText: String,
) -> String {
    currentEditingWorkspaceName == fieldWorkspaceName ? newText : currentEditingText
}

func workspaceSidebarHoverCueWidth(collapsedWidth: CGFloat, expandedWidth: CGFloat) -> CGFloat {
    collapsedWidth + min(max(expandedWidth - collapsedWidth, 0), workspaceSidebarHoverCueWidthDelta)
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

func workspaceSidebarEditorEndEditingAction(textMovement: Int?) -> WorkspaceSidebarEditorEndEditingAction {
    textMovement == NSTextMovement.cancel.rawValue ? .cancel : .commit
}

@MainActor
func normalizedWorkspaceSidebarCommittedLabel(workspaceName: String, editingText: String) -> String? {
    let normalized = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }
    return normalized == workspaceDefaultDisplayName(workspaceName) ? nil : normalized
}

@MainActor
func dispatchWorkspaceSidebarEditorEndEditingAction(
    textMovement: Int?,
    onCommit: @escaping @MainActor () -> Void,
    onCancel: @escaping @MainActor () -> Void,
) {
    let action = workspaceSidebarEditorEndEditingAction(textMovement: textMovement)
    Task { @MainActor in
        switch action {
            case .commit:
                onCommit()
            case .cancel:
                onCancel()
        }
    }
}

func canStartWorkspaceSidebarTypingRename(
    isAppEnabled: Bool,
    isSidebarEnabled: Bool,
    isSidebarVisible: Bool,
    isSidebarExpanded: Bool,
    isPanelKeyWindow: Bool,
    editingWorkspaceName: String?,
    hoveredWorkspaceName: String?,
) -> Bool {
    isAppEnabled &&
        isSidebarEnabled &&
        isSidebarVisible &&
        isSidebarExpanded &&
        isPanelKeyWindow &&
        editingWorkspaceName == nil &&
        hoveredWorkspaceName != nil
}

@MainActor
final class WorkspaceSidebarPanel: NSPanelHud {
    static let shared = WorkspaceSidebarPanel()

    private let hostingView = NSHostingView(rootView: WorkspaceSidebarView(viewModel: TrayMenuModel.shared))
    private var localRenameKeyMonitor: Any?
    private var pendingExpand: DispatchWorkItem?
    private var pendingCollapse: DispatchWorkItem?
    private var pendingCollapseFinalize: DispatchWorkItem?
    private var hoverMonitorTimer: Timer?
    private let hoverExitTolerance: CGFloat = 20
    private let hoverPollInterval: TimeInterval = 1.0 / 30.0
    private let hoverOpenDelay: TimeInterval = 0.15
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
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        installRenameKeyMonitoring()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func prepareForTextInput() {
        orderFrontRegardless()
        if !NSApp.isActive {
            NSApp.setActivationPolicy(.accessory)
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
            NSApp.activate(ignoringOtherApps: true)
        }
        if !isKeyWindow {
            makeKeyAndOrderFront(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        if handleWorkspaceRenameKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }

    func refresh() {
        guard TrayMenuModel.shared.isEnabled,
              config.workspaceSidebar.enabled,
              let monitor = config.workspaceSidebar.resolvedMonitor(sortedMonitors: sortedMonitors),
              let screen = NSScreen.screens.getOrNil(atIndex: monitor.monitorAppKitNsScreenScreensId - 1)
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
        let frame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: expandedWidth,
            height: screenFrame.height,
        )

        if self.frame != frame {
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
        guard hoverMonitorTimer == nil else { return }
        hoverMonitorTimer = Timer.scheduledTimer(withTimeInterval: hoverPollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateHoverStateFromMousePosition()
            }
        }
        RunLoop.main.add(hoverMonitorTimer!, forMode: .common)
    }

    private func stopHoverMonitoring() {
        pendingExpand?.cancel()
        pendingExpand = nil
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
        hoverMonitorTimer?.invalidate()
        hoverMonitorTimer = nil
    }

    private func resetHiddenSidebarState() {
        workspaceSidebarDropTargets = []
        TrayMenuModel.shared.workspaceSidebarDropPreview = nil
        TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = nil
        TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName = nil
        TrayMenuModel.shared.workspaceSidebarEditingText = ""
        TrayMenuModel.shared.workspaceSidebarVisibleWidth = 0
        orderOut(nil)
    }

    private func updateHoverStateFromMousePosition() {
        updateMousePassthrough()
        setHovering(isMouseInsideHoverRegion())
    }

    private func installRenameKeyMonitoring() {
        guard localRenameKeyMonitor == nil else { return }
        localRenameKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === self || self.isKeyWindow else { return event }
            let snapshot = WorkspaceSidebarRenameKeyEvent(event)
            let handled = MainActor.assumeIsolated {
                handleWorkspaceRenameTypingEvent(snapshot)
            }
            return handled ? nil : event
        }
    }

    private func shouldLockExpansionForSidebarDrag() -> Bool {
        shouldLockWorkspaceSidebarExpansion(
            hasDropPreview: TrayMenuModel.shared.workspaceSidebarDropPreview != nil,
            hasPinnedDraggedWindow: hasPinnedDraggedWindow(),
            isSidebarDragInProgress: getCurrentMouseManipulationKind() == .move && getCurrentMouseDragStartedInSidebar(),
            hasActiveEditor: TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName != nil,
        ) || isMouseWindowDragInProgress()
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
            pendingCollapse?.cancel()
            pendingCollapse = nil
            pendingCollapseFinalize?.cancel()
            pendingCollapseFinalize = nil

            if !shouldDelayWorkspaceSidebarExpansion(
                isExpanded: TrayMenuModel.shared.isWorkspaceSidebarExpanded,
                isExpansionLocked: isExpansionLocked,
                isMouseWindowDragInProgress: isMouseWindowDragInProgress(),
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
private func normalizedWorkspaceRenameSeed(from event: NSEvent) -> String? {
    normalizedWorkspaceRenameSeed(
        modifierFlags: event.modifierFlags,
        characters: event.characters,
    )
}

private func normalizedWorkspaceRenameSeed(
    modifierFlags: NSEvent.ModifierFlags,
    characters: String?,
) -> String? {
    let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
    guard modifierFlags.intersection(disallowedModifiers).isEmpty else { return nil }
    guard let characters = characters?.trimmingCharacters(in: .controlCharacters),
          !characters.isEmpty
    else { return nil }
    return characters
}

@MainActor
private func hoveredWorkspaceReadyForTypingRename() -> String? {
    guard canStartWorkspaceSidebarTypingRename(
        isAppEnabled: TrayMenuModel.shared.isEnabled,
        isSidebarEnabled: config.workspaceSidebar.enabled,
        isSidebarVisible: WorkspaceSidebarPanel.shared.isVisible,
        isSidebarExpanded: TrayMenuModel.shared.isWorkspaceSidebarExpanded,
        isPanelKeyWindow: WorkspaceSidebarPanel.shared.isKeyWindow,
        editingWorkspaceName: TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName,
        hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
    ),
    let hoveredWorkspaceName = TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName
    else {
        return nil
    }
    return hoveredWorkspaceName
}

@MainActor
private func workspaceSidebarEditorHasKeyboardFocus() -> Bool {
    guard WorkspaceSidebarPanel.shared.isKeyWindow else { return false }
    let firstResponder = WorkspaceSidebarPanel.shared.firstResponder
    return firstResponder is NSText || firstResponder is NSTextField
}

@MainActor
private func handleWorkspaceRenameTypingEvent(_ event: WorkspaceSidebarRenameKeyEvent) -> Bool {
    guard let seed = normalizedWorkspaceRenameSeed(
        modifierFlags: event.modifierFlags,
        characters: event.characters,
    ) else {
        return false
    }
    if TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName != nil {
        guard !workspaceSidebarEditorHasKeyboardFocus() else { return false }
        guard WorkspaceSidebarPanel.shared.isVisible,
              TrayMenuModel.shared.isWorkspaceSidebarExpanded,
              WorkspaceSidebarPanel.shared.isKeyWindow
        else {
            return false
        }
        TrayMenuModel.shared.workspaceSidebarEditingText += seed
        return true
    }
    guard let hoveredWorkspaceName = hoveredWorkspaceReadyForTypingRename() else { return false }
    beginWorkspaceSidebarEditing(workspaceName: hoveredWorkspaceName, initialText: seed)
    return true
}

@MainActor
private func handleWorkspaceRenameKeyDown(_ event: NSEvent) -> Bool {
    if event.keyCode == 53, let editing = TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName {
        cancelWorkspaceSidebarEditing(workspaceName: editing)
        return true
    }
    if event.keyCode == 36, let editing = TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName {
        commitWorkspaceSidebarEditing(workspaceName: editing)
        return true
    }
    return handleWorkspaceRenameTypingEvent(WorkspaceSidebarRenameKeyEvent(event))
}

@MainActor
private func focusWorkspaceFromSidebar(_ workspaceName: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            _ = Workspace.existing(byName: workspaceName)?.focusWorkspace()
        }
    }
}

@MainActor
private func beginWorkspaceSidebarEditing(workspaceName: String, initialText: String? = nil) {
    let plan = planWorkspaceSidebarBeginEditing(
        currentEditingWorkspaceName: TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName,
        currentEditingText: TrayMenuModel.shared.workspaceSidebarEditingText,
        targetWorkspaceName: workspaceName,
        targetInitialText: initialText,
        targetPersistedLabel: config.workspaceSidebar.workspaceLabels[workspaceName],
    )
    if let workspaceToCommit = plan.workspaceToCommit {
        commitWorkspaceSidebarEditing(workspaceName: workspaceToCommit)
    }
    TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName = plan.nextEditingWorkspaceName
    TrayMenuModel.shared.workspaceSidebarEditingText = plan.nextEditingText
}

@MainActor
private func cancelWorkspaceSidebarEditing(workspaceName: String) {
    guard TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName == workspaceName else { return }
    TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName = nil
    TrayMenuModel.shared.workspaceSidebarEditingText = ""
}

@MainActor
private func commitWorkspaceSidebarEditing(workspaceName: String) {
    guard TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName == workspaceName else { return }
    let normalized = normalizedWorkspaceSidebarCommittedLabel(
        workspaceName: workspaceName,
        editingText: TrayMenuModel.shared.workspaceSidebarEditingText,
    )
    TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName = nil
    TrayMenuModel.shared.workspaceSidebarEditingText = ""
    applyWorkspaceLabelFromSidebar(workspaceName: workspaceName, label: normalized)
}

@MainActor
private func applyWorkspaceLabelFromSidebar(workspaceName: String, label: String?) {
    Task { @MainActor in
        do {
            try persistWorkspaceSidebarLabel(workspaceName: workspaceName, label: label)
            config.workspaceSidebar.workspaceLabels[workspaceName] = label
            if label == nil {
                _ = config.workspaceSidebar.workspaceLabels.removeValue(forKey: workspaceName)
            }
            updateTrayText()
            await updateWorkspaceSidebarModel()
        } catch {
            MessageModel.shared.message = Message(
                description: "Workspace Label Update Failed",
                body: error.localizedDescription,
            )
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
private func sidebarWorkspaceTargetMonitor(fallbackWindow: Window? = nil) -> Monitor {
    config.workspaceSidebar.resolvedMonitor(sortedMonitors: sortedMonitors)
        ?? fallbackWindow?.nodeMonitor
        ?? focus.workspace.workspaceMonitor
}

@MainActor
private func createWorkspaceFromSidebarButton() {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    let workspaceName = nextSidebarDraftWorkspaceName()
    Task { @MainActor in
        do {
            try await runLightSession(.menuBarButton, token) {
                let workspace = Workspace.get(byName: workspaceName)
                workspace.markAsSidebarManaged()
                workspace.seedMonitorIfNeeded(sidebarWorkspaceTargetMonitor())
                _ = workspace.focusWorkspace()
            }
        } catch {
            showWorkspaceSidebarError(error.localizedDescription)
        }
    }
}

@MainActor
func createWorkspaceFromSidebarDrag(sourceNode: TreeNode, sourceWindow: Window) -> Bool {
    let workspaceName = nextSidebarDraftWorkspaceName()
    let workspace = Workspace.get(byName: workspaceName)
    workspace.markAsSidebarManaged()
    workspace.seedMonitorIfNeeded(sidebarWorkspaceTargetMonitor(fallbackWindow: sourceWindow))
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
private func focusWindowFromSidebar(_ windowId: UInt32, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
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
}

@MainActor
private func updateSidebarWindowDrag(_ windowId: UInt32, subject: WindowDragSubject = .window) {
    guard let window = Window.get(byId: windowId) else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    _ = beginWindowMoveWithMouseSessionIfNeeded(
        windowId: window.windowId,
        subject: subject,
        detachOrigin: .window,
        startedInSidebar: true,
        anchorRect: resolvedDraggedWindowAnchorRect(for: window, subject: subject),
    )
    _ = updatePendingWindowDragIntent(sourceWindow: window, mouseLocation: mouseLocation, subject: subject, detachOrigin: .window)
}

@MainActor
private func finishSidebarWindowDrag() {
    Task { @MainActor in
        try? await resetManipulatedWithMouseIfPossible()
    }
}

struct WorkspaceSidebarView: View {
    @ObservedObject var viewModel: TrayMenuModel
    @FocusState private var focusedWorkspaceEditor: String?

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
    }

    private func sidebarContent(expansionProgress: CGFloat) -> some View {
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.workspaceSidebarWorkspaces) { workspace in
                    WorkspaceSidebarWorkspaceSection(
                        workspace: workspace,
                        dragPreview: viewModel.workspaceSidebarDropPreview,
                        expansionProgress: expansionProgress,
                        isEditing: viewModel.workspaceSidebarEditingWorkspaceName == workspace.name,
                        editingText: editingBinding(for: workspace.name),
                        focusedWorkspaceEditor: $focusedWorkspaceEditor,
                        onBeginEditing: {
                            beginWorkspaceSidebarEditing(workspaceName: workspace.name)
                        },
                        onCommitEditing: {
                            commitWorkspaceSidebarEditing(workspaceName: workspace.name)
                        },
                        onCancelEditing: {
                            cancelWorkspaceSidebarEditing(workspaceName: workspace.name)
                        }
                    )
                }
                WorkspaceSidebarCreateWorkspaceSection(
                    dragPreview: viewModel.workspaceSidebarDropPreview,
                    expansionProgress: expansionProgress,
                    onCreateWorkspace: createWorkspaceFromSidebarButton
                )
            }
            .padding(.leading, workspaceSidebarContentLeadingInset)
            .padding(.trailing, workspaceSidebarContentTrailingInset)
            .padding(.top, viewModel.workspaceSidebarTopPadding)
            .padding(.bottom, 12)
        }
        .coordinateSpace(name: "workspaceSidebarContent")
        .onPreferenceChange(WorkspaceSidebarDropTargetPreferenceKey.self) { frames in
            WorkspaceSidebarPanel.shared.updateDropTargets(frames)
        }
        .background(sidebarSurface)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(width: 1)
        }
        .onAppear {
            focusedWorkspaceEditor = viewModel.workspaceSidebarEditingWorkspaceName
        }
        .onChange(of: viewModel.workspaceSidebarEditingWorkspaceName) { workspaceName in
            focusedWorkspaceEditor = workspaceName
        }
    }

    private var sidebarSurface: some View {
        VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
            .ignoresSafeArea()
    }

    private func editingBinding(for workspaceName: String) -> Binding<String> {
        Binding(
            get: {
                viewModel.workspaceSidebarEditingWorkspaceName == workspaceName
                    ? viewModel.workspaceSidebarEditingText
                    : ""
            },
            set: { newValue in
                viewModel.workspaceSidebarEditingText = nextWorkspaceSidebarEditingText(
                    currentEditingWorkspaceName: viewModel.workspaceSidebarEditingWorkspaceName,
                    fieldWorkspaceName: workspaceName,
                    currentEditingText: viewModel.workspaceSidebarEditingText,
                    newText: newValue,
                )
            },
        )
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

private struct WorkspaceSidebarEditorField: NSViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> WorkspaceSidebarEditorNSTextField {
        let view = WorkspaceSidebarEditorNSTextField()
        view.delegate = context.coordinator
        view.isEditable = true
        view.isSelectable = true
        view.isEnabled = true
        view.drawsBackground = false
        view.isBordered = false
        view.isBezeled = false
        view.focusRingType = .none
        view.font = .systemFont(ofSize: 12, weight: .semibold)
        view.textColor = .labelColor
        view.lineBreakMode = .byTruncatingTail
        view.usesSingleLineMode = true
        view.maximumNumberOfLines = 1
        view.target = context.coordinator
        view.action = #selector(Coordinator.commitFromAction)
        view.onCancel = onCancel
        view.onCommit = onCommit
        return view
    }

    func updateNSView(_ nsView: WorkspaceSidebarEditorNSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
        nsView.onCommit = onCommit
        nsView.onCancel = onCancel
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if isFocused {
            DispatchQueue.main.async {
                guard let window = nsView.window else { return }
                let currentEditor = nsView.currentEditor()
                let isAlreadyEditingThisField =
                    window.firstResponder === nsView ||
                    (currentEditor != nil && window.firstResponder === currentEditor)
                guard !isAlreadyEditingThisField else { return }
                WorkspaceSidebarPanel.shared.prepareForTextInput()
                guard window.makeFirstResponder(nsView) else { return }
                let insertionPoint = nsView.stringValue.count
                let editor = nsView.currentEditor() ?? window.fieldEditor(true, for: nsView)
                editor?.selectedRange = NSRange(location: insertionPoint, length: 0)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onCommit: () -> Void
        var onCancel: () -> Void

        init(text: Binding<String>, onCommit: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        @objc func commitFromAction() {
            onCommit()
        }
    }
}

private final class WorkspaceSidebarEditorNSTextField: NSTextField {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        let onCommit = onCommit
        let onCancel = onCancel
        dispatchWorkspaceSidebarEditorEndEditingAction(
            textMovement: notification.userInfo?["NSTextMovement"] as? Int,
            onCommit: { onCommit?() },
            onCancel: { onCancel?() },
        )
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
            case 36:
                onCommit?()
            case 53:
                onCancel?()
            default:
                super.keyDown(with: event)
        }
    }
}

struct WorkspaceSidebarWorkspaceSection: View {
    let workspace: WorkspaceSidebarWorkspaceViewModel
    let dragPreview: WorkspaceSidebarDropPreviewViewModel?
    let expansionProgress: CGFloat
    let isEditing: Bool
    let editingText: Binding<String>
    let focusedWorkspaceEditor: FocusState<String?>.Binding
    let onBeginEditing: () -> Void
    let onCommitEditing: () -> Void
    let onCancelEditing: () -> Void

    @State private var isHovered = false
    @State private var hoveredWindowId: UInt32? = nil

    private let headerHeight: CGFloat = 26
    private let rowHeight: CGFloat = 22

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
        sectionContent
            .padding(.vertical, 6)
            .padding(.horizontal, workspaceSidebarSectionInnerHorizontalInset)
            .frame(width: sectionWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .onHover { hover in
                isHovered = hover
                TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = nextWorkspaceSidebarHoveredWorkspaceName(
                    currentHoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
                    workspaceName: workspace.name,
                    isHovering: hover,
                )
            }
            .gesture(TapGesture().onEnded {
                if shouldHandleWorkspaceSidebarActivation(
                    editingWorkspaceName: TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName,
                    isSidebarDragInProgress: isWorkspaceSidebarDragInProgress(),
                ) {
                    focusWorkspaceFromSidebar(workspace.name)
                }
            }, including: .gesture)
            .zIndex(isDropTarget ? 1 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.86), value: dragPreview)
            .animation(.spring(response: 0.22, dampingFraction: 0.86), value: expansionProgress)
            .contextMenu {
                Button("Rename Workspace…") {
                    onBeginEditing()
                }
                if !workspace.sidebarLabel.isEmpty {
                    Button("Remove Workspace Label") {
                        applyWorkspaceLabelFromSidebar(workspaceName: workspace.name, label: nil)
                    }
                }
            }
            .background(sectionBackground)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: WorkspaceSidebarDropTargetPreferenceKey.self,
                        value: [WorkspaceSidebarDropTargetFrame(
                            kind: .workspace(workspace.name),
                            frame: geometry.frame(in: .named("workspaceSidebarContent")),
                        )],
                    )
                }
            }
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            header
                .frame(height: headerHeight)
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
            windowRows
            dropPreviewRow
        }
    }

    @ViewBuilder
    private var windowRows: some View {
        if showsWindowRows, !workspace.items.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(workspace.items) { item in
                    workspaceItemView(item)
                }
            }
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

    private func workspaceWindowButton(_ window: WorkspaceSidebarWindowViewModel, allowsDrag: Bool, subject: WindowDragSubject = .window) -> some View {
        Button {
            guard shouldHandleWorkspaceSidebarActivation(
                editingWorkspaceName: TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName,
                isSidebarDragInProgress: isWorkspaceSidebarDragInProgress(),
            ) else { return }
            focusWindowFromSidebar(window.windowId, fallbackWorkspace: window.workspaceName)
        } label: {
            WorkspaceSidebarWindowRow(
                window: window,
                expansionProgress: expansionProgress,
                rowHeight: rowHeight,
                isHovered: hoveredWindowId == window.windowId,
                expandedContentWidth: contentWidth
            )
        }
        .buttonStyle(.plain)
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
        .opacity(activeSidebarDragSourceWindowId == window.windowId ? 0.3 : 1)
        .scaleEffect(activeSidebarDragSourceWindowId == window.windowId ? 0.96 : 1)
    }

    private func workspaceTabGroupView(_ group: WorkspaceSidebarTabGroupViewModel) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                guard shouldHandleWorkspaceSidebarActivation(
                    editingWorkspaceName: TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName,
                    isSidebarDragInProgress: isWorkspaceSidebarDragInProgress(),
                ) else { return }
                focusWindowFromSidebar(group.representativeWindowId, fallbackWorkspace: group.workspaceName)
            } label: {
                WorkspaceSidebarTabGroupRow(
                    group: group,
                    expansionProgress: expansionProgress,
                    rowHeight: rowHeight,
                    expandedContentWidth: contentWidth
                )
            }
            .buttonStyle(.plain)
            .modifier(WorkspaceSidebarOptionalDragModifier(
                isEnabled: true,
                onChanged: {
                    updateSidebarWindowDrag(group.representativeWindowId, subject: .group)
                },
                onEnded: {
                    finishSidebarWindowDrag()
                },
            ))
            .opacity(activeSidebarDragSourceWindowId == group.representativeWindowId ? 0.3 : 1)
            .scaleEffect(activeSidebarDragSourceWindowId == group.representativeWindowId ? 0.96 : 1)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(group.tabs) { tab in
                    workspaceWindowButton(tab, allowsDrag: true, subject: .window)
                        .padding(.leading, 10)
                }
            }
        }
    }

    // MARK: - Section Background

    private var sectionBackground: some View {
        sectionShape
            .fill(sectionBackgroundFill)
            .overlay {
                sectionShape
                    .strokeBorder(sectionBorderColor, lineWidth: isDropTarget ? 1.5 : 0.5)
            }
    }

    // MARK: - Header

    private var header: some View {
        Group {
            if isCompact {
                workspaceBadge
                    .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack(spacing: workspaceSidebarHeaderSpacing) {
                    workspaceBadge
                        .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth, alignment: .center)
                    VStack(alignment: .leading, spacing: 0) {
                        if isEditing {
                            WorkspaceSidebarEditorField(
                                text: editingText,
                                isFocused: focusedWorkspaceEditor.wrappedValue == workspace.name,
                                onCommit: onCommitEditing,
                                onCancel: onCancelEditing
                            )
                            .frame(height: 18)
                            .focused(focusedWorkspaceEditor, equals: workspace.name)
                        } else {
                            Text(workspace.displayName)
                                .font(.system(size: 12, weight: workspace.isFocused ? .semibold : .medium))
                                .foregroundStyle(workspace.isFocused ? Color.primary : Color.secondary)
                                .lineLimit(1)
                        }
                        if let monitorName = workspace.monitorName, !isEditing, showsWindowRows {
                            Text(monitorName)
                                .font(.system(size: 9, weight: .regular))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if isEditing {
                        HStack(spacing: 4) {
                            Button(action: onCommitEditing) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            Button(action: onCancelEditing) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
        }
    }

    private var sectionBackgroundFill: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.15)
        } else if isHovered {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        } else if workspace.isFocused {
            return Color(nsColor: .controlBackgroundColor).opacity(0.6)
        } else if workspace.isVisible && expansionProgress > 0.5 {
            return Color(nsColor: .controlBackgroundColor).opacity(0.28)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.12)
    }

    private var sectionBorderColor: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.6)
        }
        if workspace.isFocused {
            return Color.accentColor.opacity(0.12)
        }
        return Color.primary.opacity(0.04)
    }

    private var workspaceBadge: some View {
        Group {
            if workspace.isGeneratedName, workspace.sidebarLabel.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
            } else if workspace.isGeneratedName, let initial = workspace.displayName.first {
                Text(String(initial).uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            } else {
                Text(workspace.name)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
        }
        .foregroundStyle(workspace.isFocused ? Color.white : Color.primary)
        .lineLimit(1)
        .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(workspace.isFocused ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.8))
        )
    }
}

// MARK: - Create Workspace Section

struct WorkspaceSidebarCreateWorkspaceSection: View {
    let dragPreview: WorkspaceSidebarDropPreviewViewModel?
    let expansionProgress: CGFloat
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
                guard shouldHandleWorkspaceSidebarActivation(
                    editingWorkspaceName: TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName,
                    isSidebarDragInProgress: isWorkspaceSidebarDragInProgress(),
                ) else { return }
                onCreateWorkspace()
            } label: {
                Group {
                    if isCompact {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)
                    } else {
                        HStack(spacing: workspaceSidebarHeaderSpacing) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth, alignment: .center)
                                .foregroundStyle(Color.accentColor)
                            Text("New Workspace")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.secondary)
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
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(isDropTarget ? 0.3 : (isHovered ? 0.3 : 0.12)))
                        .overlay {
                            sectionShape
                                .strokeBorder(Color.accentColor.opacity(isDropTarget ? 0.45 : 0.08), lineWidth: isDropTarget ? 1.5 : 0.5)
                        }
                )
            }
            .buttonStyle(.plain)
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
        .animation(.spring(response: 0.22, dampingFraction: 0.84), value: dragPreview)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: WorkspaceSidebarDropTargetPreferenceKey.self,
                    value: [WorkspaceSidebarDropTargetFrame(
                        kind: .newWorkspace,
                        frame: geometry.frame(in: .named("workspaceSidebarContent")),
                    )],
                )
            }
        }
    }
}

// MARK: - Window Row

struct WorkspaceSidebarWindowRow: View {
    let window: WorkspaceSidebarWindowViewModel
    let expansionProgress: CGFloat
    let rowHeight: CGFloat
    let isHovered: Bool
    let expandedContentWidth: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(window.isFocused ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 5, height: 5)
            Text(window.title ?? window.appName)
                .font(.system(size: 11, weight: window.isFocused ? .medium : .regular))
                .foregroundStyle(window.isFocused ? Color.primary : Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.4) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Tab Group Row

struct WorkspaceSidebarTabGroupRow: View {
    let group: WorkspaceSidebarTabGroupViewModel
    let expansionProgress: CGFloat
    let rowHeight: CGFloat
    let expandedContentWidth: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(group.isFocused ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.2))
                    .frame(width: 9, height: 6)
                    .offset(x: -1.5, y: -1.5)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(group.isFocused ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.35))
                    .frame(width: 9, height: 6)
                    .offset(x: 1.5, y: 1.5)
            }
            .frame(width: 16, height: 16)

            Text(group.title.isEmpty ? "Tab Group" : group.title)
                .font(.system(size: 11, weight: group.isFocused ? .medium : .regular))
                .foregroundStyle(group.isFocused ? Color.primary : Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(group.windowCount)")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .opacity(expansionProgress)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(height: rowHeight + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(group.isFocused ? Color.accentColor.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Drop Preview Row

struct WorkspaceSidebarPreviewRow: View {
    let preview: WorkspaceSidebarDropPreviewViewModel
    let expansionProgress: CGFloat
    let rowHeight: CGFloat
    let expandedContentWidth: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: preview.isTabGroup ? "square.stack" : "macwindow")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.6))
                .frame(width: 16, height: 16)
            Text(preview.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.6))
                .lineLimit(1)
                .opacity(expansionProgress)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(height: rowHeight + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
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
