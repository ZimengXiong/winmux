import AppKit
import SwiftUI

private let workspaceSidebarPanelId = "WinMux.workspaceSidebar"
private let workspaceSidebarContentLeadingInset: CGFloat = 8
private let workspaceSidebarContentTrailingInset: CGFloat = 8
private let workspaceSidebarCompactRailHorizontalInset: CGFloat = 4
private let workspaceSidebarSectionInnerHorizontalInset: CGFloat = 4
private let workspaceSidebarBadgeWidth: CGFloat = 22
private let workspaceSidebarHeaderSpacing: CGFloat = 8
private let workspaceSidebarRowsRevealProgress: CGFloat = 0.58
private let workspaceSidebarOuterCornerRadius: CGFloat = 16
private let workspaceSidebarSectionCornerRadius: CGFloat = 8
private let workspaceSidebarRowCornerRadius: CGFloat = 6
private let workspaceSidebarRowHorizontalPadding: CGFloat = 7
private let workspaceSidebarPagerHeight: CGFloat = 42
private let workspaceSidebarHoverOpenThresholdFraction: CGFloat = 0.75
private let workspaceSidebarDisplayEdgeCompactionMargin: CGFloat = 12
@MainActor
private var workspaceSidebarDropTargets: [WorkspaceSidebarDropTarget] = []

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
    private var hoverMonitorTimer: Timer?
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
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

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
            hasActiveEditor: false,
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
private func sidebarWorkspaceTargetMonitor(fallbackWindow: Window? = nil) -> Monitor {
    if let selectedMonitor = selectedWorkspaceSidebarMonitorScope() {
        return selectedMonitor
    }
    return fallbackWindow?.nodeMonitor ?? focus.workspace.workspaceMonitor
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
        let workspaceName = nextSidebarCreatedWorkspaceName(projectId: projectId, monitor: targetMonitor)
        let workspace = Workspace.get(byName: workspaceName)
        workspace.markAsSidebarManaged()
        workspace.assignProject(projectId)
        workspace.seedMonitorIfNeeded(targetMonitor)
        _ = workspace.focusWorkspace()
    }
}

@MainActor
func createWorkspaceFromSidebarDrag(sourceNode: TreeNode, sourceWindow: Window) -> Bool {
    let targetMonitor = sidebarWorkspaceTargetMonitor(fallbackWindow: sourceWindow)
    let projectId = sidebarWorkspaceTargetProjectId(targetMonitor: targetMonitor)
    let workspaceName = nextSidebarCreatedWorkspaceName(projectId: projectId, monitor: targetMonitor)
    let workspace = Workspace.get(byName: workspaceName)
    workspace.markAsSidebarManaged()
    workspace.assignProject(projectId)
    workspace.seedMonitorIfNeeded(targetMonitor)
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
private func sidebarWorkspaceTargetProjectId(targetMonitor: Monitor) -> String {
    let selectedProjectId = TrayMenuModel.shared.workspaceSidebarSelectedProjectId
    guard workspaceProjects().contains(where: { $0.id == selectedProjectId }) else {
        return activeWorkspaceProjectId(for: targetMonitor)
    }
    return selectedProjectId
}

@MainActor
private func selectWorkspaceSidebarProject(_ projectId: String) {
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
private func deleteWorkspaceSidebarProject(_ project: WorkspaceSidebarProjectViewModel) {
    guard canDeleteWorkspaceProject(project.id) else { return }
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
        let isCompact = expansionProgress < workspaceSidebarRowsRevealProgress
        let leadingInset = isCompact ? workspaceSidebarCompactRailHorizontalInset : workspaceSidebarContentLeadingInset
        let trailingInset = isCompact ? workspaceSidebarCompactRailHorizontalInset : workspaceSidebarContentTrailingInset
        let showsMonitorSelector = !isCompact && viewModel.workspaceSidebarShowsMonitorSelector

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

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.visibleWorkspaceSidebarWorkspaces) { workspace in
                        WorkspaceSidebarWorkspaceSection(
                            workspace: workspace,
                            dragPreview: viewModel.workspaceSidebarDropPreview,
                            expansionProgress: expansionProgress
                        )
                    }
                    WorkspaceSidebarCreateWorkspaceSection(
                        dragPreview: viewModel.workspaceSidebarDropPreview,
                        expansionProgress: expansionProgress,
                        onCreateWorkspace: createWorkspaceFromSidebarButton
                    )
                }
                .padding(.leading, leadingInset)
                .padding(.trailing, trailingInset)
                .padding(.top, showsMonitorSelector ? 0 : viewModel.workspaceSidebarTopPadding)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: "workspaceSidebarContent")
            .onPreferenceChange(WorkspaceSidebarDropTargetPreferenceKey.self) { frames in
                WorkspaceSidebarPanel.shared.updateDropTargets(frames)
            }

            WorkspaceSidebarProjectPager(
                projects: viewModel.workspaceSidebarProjects,
                selectedProjectId: viewModel.workspaceSidebarSelectedProjectId,
                expansionProgress: expansionProgress,
            )
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
            .padding(.bottom, 10)
        }
        .background {
            sidebarSurface(in: sidebarShape)
        }
        .environment(\.colorScheme, .dark)
        .clipShape(sidebarShape)
        .overlay(alignment: .trailing) {
            if !usesNativeLiquidGlass {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 0.5)
            }
        }
        .shadow(
            color: Color.black.opacity(usesNativeLiquidGlass ? 0 : 0.32),
            radius: usesNativeLiquidGlass ? 0 : 14,
            x: usesNativeLiquidGlass ? 0 : 2,
            y: 0
        )
    }

    private var sidebarShape: some Shape {
        UnevenRoundedRectangle(
            bottomTrailingRadius: workspaceSidebarOuterCornerRadius,
            topTrailingRadius: topTrailingCornerRadius,
            style: .continuous
        )
    }

    private func sidebarSurface<S: Shape>(in shape: S) -> some View {
        liquidGlassBackground(in: shape, isInteractive: true) {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color.black.opacity(0.42))
        }
        .ignoresSafeArea()
    }

    private var topTrailingCornerRadius: CGFloat {
        config.workspaceSidebar.menuBarReserveHeight == 0 ? 0 : workspaceSidebarOuterCornerRadius
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
    let selectedProjectId: String
    let expansionProgress: CGFloat

    @State private var isHovered = false
    @State private var pressedProjectId: String? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var editingProjectId: String? = nil
    @State private var editingProjectDraft = ""
    @FocusState private var isRenameFieldFocused: Bool

    private var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress) }
    private var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    private var pagerControlWidth: CGFloat { 34 }
    private var pagerControlHeight: CGFloat { 34 }
    private var currentIndex: Int? {
        projects.firstIndex { $0.id == selectedProjectId }
            ?? projects.indices.first
    }

    var body: some View {
        if !projects.isEmpty {
            pagerContent
                .frame(width: sectionWidth, height: workspaceSidebarPagerHeight, alignment: .center)
                .background(pagerBackground)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onHover { hovering in
                    isHovered = hovering
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            dragTranslation = value.translation.width
                            dragOffset = resistedDragOffset(for: value.translation.width)
                        }
                        .onEnded { value in
                            defer {
                                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                                    dragOffset = 0
                                    dragTranslation = 0
                                }
                            }
                            handlePagerDragEnd(value.translation.width)
                        },
                )
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: isHovered)
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: currentIndex)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
        }
    }

    private var pagerContent: some View {
        HStack(spacing: isCompact ? 2 : 6) {
            if !isCompact {
                pagerControl(systemImage: "plus", accessibilityLabel: "New Project Left", controlId: "new-left") {
                    createWorkspaceSidebarProject()
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: isHovered ? 7 : 5) {
                    if leadingNewProjectProgress > 0 {
                        formingProjectDot(progress: leadingNewProjectProgress)
                            .transition(.scale(scale: 0.45).combined(with: .opacity))
                    }
                    ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                        projectDot(project, index: index)
                    }
                    if trailingNewProjectProgress > 0 {
                        formingProjectDot(progress: trailingNewProjectProgress)
                            .transition(.scale(scale: 0.45).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, isCompact ? 2 : 5)
                .frame(minWidth: projectDotsMinWidth, alignment: .center)
                .offset(x: dragOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if !isCompact {
                pagerControl(systemImage: "plus", accessibilityLabel: "New Project Right", controlId: "new-right") {
                    createWorkspaceSidebarProject()
                }
            }
        }
        .padding(.horizontal, isCompact ? 2 : 4)
        .background {
            WorkspaceSidebarProjectPagerScrollWheelCapture { delta in
                guard editingProjectId == nil else { return }
                navigateProjectPager(direction: delta > 0 ? 1 : -1)
            }
        }
    }

    private var projectDotsMinWidth: CGFloat {
        if isCompact {
            return max(sectionWidth - 4, 12)
        }
        return max(sectionWidth - (pagerControlWidth * 2) - 24, 24)
    }

    private var pagerBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(pagerFill)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.10 : 0.055), lineWidth: 0.5)
            }
    }

    private var pagerFill: Color {
        Color.white.opacity(isHovered ? 0.055 : 0.032)
    }

    private var leadingNewProjectProgress: CGFloat {
        newProjectProgress(edgeDirection: -1)
    }

    private var trailingNewProjectProgress: CGFloat {
        newProjectProgress(edgeDirection: 1)
    }

    private func newProjectProgress(edgeDirection: Int) -> CGFloat {
        guard let currentIndex else { return 0 }
        let isPullingBeforeFirst = edgeDirection < 0 && currentIndex == 0 && dragTranslation > 0
        let isPullingAfterLast = edgeDirection > 0 && currentIndex == projects.count - 1 && dragTranslation < 0
        guard isPullingBeforeFirst || isPullingAfterLast else { return 0 }
        return min(max((abs(dragTranslation) - 24) / 58, 0), 1)
    }

    private func resistedDragOffset(for translation: CGFloat) -> CGFloat {
        guard let currentIndex else { return max(-18, min(18, translation / 4)) }
        let isPullingBeforeFirst = currentIndex == 0 && translation > 0
        let isPullingAfterLast = currentIndex == projects.count - 1 && translation < 0
        let divisor: CGFloat = isPullingBeforeFirst || isPullingAfterLast ? 6 : 3
        let limit: CGFloat = isPullingBeforeFirst || isPullingAfterLast ? 30 : 18
        return max(-limit, min(limit, translation / divisor))
    }

    private func handlePagerDragEnd(_ translation: CGFloat) {
        guard abs(translation) >= 32 else { return }
        let direction = translation < 0 ? 1 : -1
        if shouldCreateProjectAfterDrag(direction: direction, translation: translation) {
            createWorkspaceSidebarProject()
        } else {
            navigateProjectPager(direction: direction)
        }
    }

    private func shouldCreateProjectAfterDrag(direction: Int, translation: CGFloat) -> Bool {
        guard let currentIndex else { return false }
        let pulledPastStart = direction < 0 && currentIndex == 0
        let pulledPastEnd = direction > 0 && currentIndex == projects.count - 1
        return (pulledPastStart || pulledPastEnd) && abs(translation) >= 82
    }

    private func navigateProjectPager(direction: Int) {
        guard !projects.isEmpty, let currentIndex else { return }
        let nextIndex = (currentIndex + direction + projects.count) % projects.count
        selectWorkspaceSidebarProject(projects[nextIndex].id)
    }

    private func beginInlineRename(_ project: WorkspaceSidebarProjectViewModel) {
        editingProjectId = project.id
        editingProjectDraft = project.displayName
        DispatchQueue.main.async {
            isRenameFieldFocused = true
        }
    }

    private func commitInlineRename(_ project: WorkspaceSidebarProjectViewModel) {
        guard editingProjectId == project.id else { return }
        let trimmed = editingProjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        editingProjectId = nil
        isRenameFieldFocused = false
        guard !trimmed.isEmpty, trimmed != project.displayName else { return }
        renameWorkspaceSidebarProject(project, displayName: trimmed)
    }

    private func pagerControl(
        systemImage: String,
        accessibilityLabel: String,
        controlId: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Color.white.opacity(isHovered ? 0.72 : 0.52))
                .frame(width: pagerControlWidth, height: pagerControlHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.075 : 0.04))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(isHovered ? 0.10 : 0.05), lineWidth: 0.5)
                        }
                )
                .scaleEffect(pressedProjectId == controlId ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressedProjectId = controlId }
                .onEnded { _ in pressedProjectId = nil },
        )
        .animation(.easeOut(duration: 0.14), value: pressedProjectId == controlId)
    }

    @ViewBuilder
    private func formingProjectDot(progress: CGFloat) -> some View {
        let clampedProgress = min(max(progress, 0), 1)
        Capsule(style: .continuous)
            .fill(Color.accentColor.opacity(0.26 + 0.52 * clampedProgress))
            .frame(
                width: 8 + 16 * clampedProgress,
                height: 7 + 2 * clampedProgress,
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08 + 0.18 * clampedProgress), lineWidth: 0.5)
            }
            .shadow(
                color: Color.accentColor.opacity(0.18 * clampedProgress),
                radius: 3 + 5 * clampedProgress,
                y: 1,
            )
            .scaleEffect(0.72 + 0.28 * clampedProgress)
            .frame(width: 22, height: 30)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.78), value: clampedProgress)
    }

    @ViewBuilder
    private func projectDot(_ project: WorkspaceSidebarProjectViewModel, index: Int) -> some View {
        let isCurrent = index == currentIndex
        let isPressed = pressedProjectId == project.id
        if editingProjectId == project.id {
            TextField("", text: $editingProjectDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .focused($isRenameFieldFocused)
                .lineLimit(1)
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
                .onSubmit {
                    commitInlineRename(project)
                }
                .onChange(of: isRenameFieldFocused) { focused in
                    if !focused, editingProjectId == project.id {
                        commitInlineRename(project)
                    }
                }
                .onAppear {
                    isRenameFieldFocused = true
                }
        } else {
            Button {
                selectWorkspaceSidebarProject(project.id)
            } label: {
                Capsule(style: .continuous)
                    .fill(dotFill(isCurrent: isCurrent))
                    .frame(
                        width: dotWidth(isCurrent: isCurrent),
                        height: dotHeight(isCurrent: isCurrent),
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(dotBorder(isCurrent: isCurrent), lineWidth: 0.5)
                    }
                    .shadow(
                        color: isCurrent ? Color.accentColor.opacity(0.24) : Color.clear,
                        radius: isCurrent ? 5 : 0,
                        y: isCurrent ? 1 : 0,
                    )
                    .scaleEffect(isPressed ? 0.96 : 1)
                    .frame(width: dotHitWidth(isCurrent: isCurrent), height: dotHitHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(project.displayName)
            .help(project.displayName)
            .contextMenu {
                Button("Rename Project") {
                    beginInlineRename(project)
                }
                Button(role: .destructive) {
                    deleteWorkspaceSidebarProject(project)
                } label: {
                    Text("Delete Project")
                }
                .disabled(!canDeleteWorkspaceProject(project.id))
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressedProjectId = project.id }
                    .onEnded { _ in pressedProjectId = nil },
            )
            .onTapGesture(count: 2) {
                beginInlineRename(project)
            }
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.84), value: isCurrent)
            .animation(.easeOut(duration: 0.14), value: isPressed)
        }
    }

    private func dotWidth(isCurrent: Bool) -> CGFloat {
        if isCurrent {
            return isHovered ? 22 : 16
        }
        return isHovered && !isCompact ? 11 : 7
    }

    private func dotHeight(isCurrent: Bool) -> CGFloat {
        if isCurrent {
            return isHovered ? 8 : 7
        }
        return isHovered && !isCompact ? 8 : 7
    }

    private func dotHitWidth(isCurrent: Bool) -> CGFloat {
        if isCompact {
            return max(dotWidth(isCurrent: isCurrent), 18)
        }
        return max(dotWidth(isCurrent: isCurrent) + 18, 34)
    }

    private var dotHitHeight: CGFloat {
        isCompact ? 28 : 34
    }

    private func dotFill(isCurrent: Bool) -> Color {
        if isCurrent {
            return Color.accentColor.opacity(0.92)
        }
        return Color.white.opacity(isHovered ? 0.42 : 0.28)
    }

    private func dotBorder(isCurrent: Bool) -> Color {
        if isCurrent {
            return Color.white.opacity(0.22)
        }
        return Color.white.opacity(isHovered ? 0.12 : 0.06)
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
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.appearance = NSAppearance(named: .darkAqua)
    }
}

private struct WorkspaceSidebarProjectPagerScrollWheelCapture: NSViewRepresentable {
    let onStep: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelCaptureView {
        let view = ScrollWheelCaptureView()
        view.onStep = onStep
        return view
    }

    func updateNSView(_ nsView: ScrollWheelCaptureView, context: Context) {
        nsView.onStep = onStep
    }

    final class ScrollWheelCaptureView: NSView {
        var onStep: ((CGFloat) -> Void)?
        private var eventMonitor: Any?
        private var accumulatedDelta: CGFloat = 0
        private let threshold: CGFloat = 14

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeEventMonitor()
            } else {
                installEventMonitor()
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        private func installEventMonitor() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScrollWheel(event)
                return event
            }
        }

        private func removeEventMonitor() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            eventMonitor = nil
        }

        private func handleScrollWheel(_ event: NSEvent) {
            guard let window, event.window === window else { return }
            let localPoint = convert(event.locationInWindow, from: nil)
            guard bounds.insetBy(dx: -6, dy: -6).contains(localPoint) else { return }

            let dominantDelta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX
                : -event.scrollingDeltaY
            accumulatedDelta += dominantDelta
            guard abs(accumulatedDelta) >= threshold else { return }
            onStep?(accumulatedDelta)
            accumulatedDelta = 0
        }
    }
}

struct WorkspaceSidebarWorkspaceSection: View {
    let workspace: WorkspaceSidebarWorkspaceViewModel
    let dragPreview: WorkspaceSidebarDropPreviewViewModel?
    let expansionProgress: CGFloat

    @State private var isHovered = false
    @State private var hoveredWindowId: UInt32? = nil

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
                    renameWorkspaceFromSidebar(workspace)
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
            .animation(.easeOut(duration: 0.15), value: isHovered)
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
                        value: [WorkspaceSidebarDropTargetFrame(
                            kind: .workspace(workspace.name),
                            frame: geometry.frame(in: .named("workspaceSidebarContent")),
                        )],
                    )
                }
            }
    }

    private func handleSectionClick() {
        if shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) {
            focusWorkspaceFromSidebar(workspace.name)
        }
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
                    isHovered: false,
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
                        Text(workspace.displayName)
                            .font(.system(size: 12.5, weight: workspace.isFocused ? .semibold : .medium))
                            .foregroundStyle(workspace.isFocused ? Color.white : Color.white.opacity(0.86))
                            .lineLimit(1)
                        if let monitorName = workspace.monitorName, showsWindowRows {
                            Text(monitorName)
                                .font(.system(size: 9.5, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.54))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var sectionBackgroundFill: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.16)
        } else if isCompact {
            if workspace.isFocused {
                return Color.white.opacity(0.10)
            } else if isHovered {
                return Color.white.opacity(0.06)
            }
        } else if workspace.isFocused {
            return Color.white.opacity(0.055)
        } else if isHovered {
            return Color.white.opacity(0.045)
        } else if workspace.isVisible && expansionProgress > 0.5 {
            return Color.white.opacity(0.02)
        }
        return Color.clear
    }

    private var sectionBorderColor: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.35)
        }
        if workspace.isFocused && !isCompact {
            return Color.white.opacity(0.06)
        }
        return Color.clear
    }

    private var workspaceBadge: some View {
        Group {
            if workspace.isGeneratedName, workspace.sidebarLabel.isEmpty {
                Text(generatedWorkspaceBadgeText)
                    .font(.system(size: 9, weight: .semibold))
            } else if workspace.isGeneratedName, let initial = workspace.displayName.first {
                Text(String(initial).uppercased())
                    .font(.system(size: 9, weight: .semibold))
            } else {
                Text(workspace.name)
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .foregroundStyle(workspace.isFocused ? Color.white : Color.white.opacity(0.84))
        .lineLimit(1)
        .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(workspaceBadgeFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(workspaceBadgeBorder, lineWidth: 0.5)
            }
        )
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

    private var workspaceBadgeFill: Color {
        if workspace.isFocused {
            return Color.accentColor.opacity(0.84)
        }
        return Color.white.opacity(isCompact ? 0.09 : 0.06)
    }

    private var workspaceBadgeBorder: Color {
        if workspace.isFocused {
            return Color.clear
        }
        return Color.white.opacity(0.08)
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
                                    isDropTarget ? Color.accentColor.opacity(0.35) : Color.white.opacity(isHovered ? 0.06 : 0),
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
                    value: [WorkspaceSidebarDropTargetFrame(
                        kind: .newWorkspace,
                        frame: geometry.frame(in: .named("workspaceSidebarContent")),
                    )],
                )
            }
        }
    }

    private var createSectionFill: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.16)
        }
        if isHovered {
            return Color.white.opacity(isCompact ? 0.08 : 0.06)
        }
        return Color.clear
    }

    private var plusBadge: some View {
        Image(systemName: "plus")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.72))
            .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(isCompact ? 0.05 : 0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    }
            )
    }
}

// MARK: - Window Row

struct WorkspaceSidebarWindowRow: View {
    let title: String
    let badge: String?
    let isFocused: Bool
    let rowHeight: CGFloat
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: isFocused ? .semibold : .regular))
                .foregroundStyle(isFocused ? Color.white : Color.white.opacity(0.78))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.52))
            }
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, 1.5)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                .fill(isFocused ? Color.white.opacity(0.13) : isHovered ? Color.white.opacity(0.07) : Color.clear)
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
        HStack(spacing: 8) {
            Text(preview.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.74))
                .lineLimit(1)
                .opacity(expansionProgress)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, 1.5)
        .frame(height: rowHeight + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(0.2),
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
