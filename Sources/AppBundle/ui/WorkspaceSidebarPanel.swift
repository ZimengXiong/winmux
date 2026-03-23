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
@MainActor
private var workspaceSidebarDropTargets: [WorkspaceSidebarDropTarget] = []

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

@MainActor
final class WorkspaceSidebarPanel: NSPanelHud {
    static let shared = WorkspaceSidebarPanel()

    private let hostingView = NSHostingView(rootView: WorkspaceSidebarView(viewModel: TrayMenuModel.shared))
    private var pendingCollapse: DispatchWorkItem?
    private var pendingCollapseFinalize: DispatchWorkItem?
    private var hoverMonitorTimer: Timer?
    private let hoverExitTolerance: CGFloat = 20
    private let hoverPollInterval: TimeInterval = 1.0 / 30.0
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
    override var canBecomeMain: Bool { true }

    func prepareForTextInput() {
        NSApp.setActivationPolicy(.accessory)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        orderFrontRegardless()
        makeMain()
        makeKey()
        makeKeyAndOrderFront(nil)
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
        TrayMenuModel.shared.workspaceSidebarDropPreview != nil || hasPinnedDraggedWindow()
    }

    private func setHovering(_ isHovering: Bool) {
        if isHovering {
            pendingCollapse?.cancel()
            pendingCollapse = nil
            pendingCollapseFinalize?.cancel()
            pendingCollapseFinalize = nil

            let sidebarConfig = config.workspaceSidebar
            let expandedWidth = CGFloat(sidebarConfig.width)
            if !TrayMenuModel.shared.isWorkspaceSidebarExpanded ||
                TrayMenuModel.shared.workspaceSidebarVisibleWidth != expandedWidth
            {
                TrayMenuModel.shared.isWorkspaceSidebarExpanded = true
                if !isVisible {
                    refresh()
                }
                withAnimation(.easeInOut(duration: animationDuration)) {
                    TrayMenuModel.shared.workspaceSidebarVisibleWidth = expandedWidth
                }
            }
        } else {
            if shouldLockExpansionForSidebarDrag() {
                return
            }
            if TrayMenuModel.shared.isWorkspaceSidebarExpanded && pendingCollapse == nil {
                let collapse = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pendingCollapse = nil
                    if !self.isMouseInsideHoverRegion() && !self.shouldLockExpansionForSidebarDrag() {
                        let sidebarConfig = config.workspaceSidebar
                        withAnimation(.easeInOut(duration: self.animationDuration)) {
                            TrayMenuModel.shared.workspaceSidebarVisibleWidth = CGFloat(sidebarConfig.collapsedWidth)
                        }
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: collapse)
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
}

@MainActor
private func normalizedWorkspaceRenameSeed(from event: NSEvent) -> String? {
    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return nil }
    guard let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .controlCharacters),
          !characters.isEmpty
    else { return nil }
    return characters
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
    guard TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName == nil,
          let hoveredWorkspaceName = TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
          let seed = normalizedWorkspaceRenameSeed(from: event)
    else {
        return false
    }
    beginWorkspaceSidebarEditing(workspaceName: hoveredWorkspaceName, initialText: seed)
    return true
}

@MainActor
private func focusWorkspaceFromSidebar(_ workspaceName: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            _ = Workspace.get(byName: workspaceName).focusWorkspace()
        }
    }
}

@MainActor
private func beginWorkspaceSidebarEditing(workspaceName: String, initialText: String? = nil) {
    TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName = workspaceName
    TrayMenuModel.shared.workspaceSidebarEditingText = initialText ?? config.workspaceSidebar.workspaceLabels[workspaceName] ?? ""
    DispatchQueue.main.async {
        WorkspaceSidebarPanel.shared.prepareForTextInput()
    }
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
    let normalized = TrayMenuModel.shared.workspaceSidebarEditingText.trimmingCharacters(in: .whitespacesAndNewlines)
    TrayMenuModel.shared.workspaceSidebarEditingWorkspaceName = nil
    TrayMenuModel.shared.workspaceSidebarEditingText = ""
    applyWorkspaceLabelFromSidebar(workspaceName: workspaceName, label: normalized.isEmpty ? nil : normalized)
}

@MainActor
private func applyWorkspaceLabelFromSidebar(workspaceName: String, label: String?) {
    Task { @MainActor in
        do {
            try persistWorkspaceSidebarLabel(workspaceName: workspaceName, label: label)
            let reloaded = try await reloadConfig()
            if !reloaded {
                MessageModel.shared.message = Message(
                    description: "Workspace Label Update Failed",
                    body: "AeroSpace couldn't reload the updated config after changing the sidebar label for workspace '\(workspaceName)'.",
                )
                return
            }
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
private func createWorkspaceFromSidebarButton() {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    let workspaceName = nextSidebarDraftWorkspaceName()
    beginWorkspaceSidebarEditing(workspaceName: workspaceName, initialText: "")
    Task { @MainActor in
        do {
            try await runLightSession(.menuBarButton, token) {
                let workspace = Workspace.get(byName: workspaceName)
                workspace.markAsSidebarManaged()
                _ = workspace.focusWorkspace()
            }
        } catch {
            cancelWorkspaceSidebarEditing(workspaceName: workspaceName)
            showWorkspaceSidebarError(error.localizedDescription)
        }
    }
}

@MainActor
func createWorkspaceFromSidebarDrag(sourceNode: TreeNode, sourceWindow: Window) -> Bool {
    let workspaceName = nextSidebarDraftWorkspaceName()
    let workspace = Workspace.get(byName: workspaceName)
    workspace.markAsSidebarManaged()
    beginWorkspaceSidebarEditing(workspaceName: workspaceName, initialText: "")
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
                _ = Workspace.get(byName: fallbackWorkspace).focusWorkspace()
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
    currentlyManipulatedWithMouseWindowId = window.windowId
    setCurrentMouseManipulationKind(.move)
    setCurrentMouseDragSubject(subject)
    setCurrentMouseTabDetachOrigin(.window)
    setDraggedWindowAnchorRect(resolvedDraggedWindowAnchorRect(for: window, subject: subject), for: window.windowId)
    WindowTabStripPanelController.shared.setIgnoresMouseEvents(true)
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
                viewModel.workspaceSidebarEditingText = newValue
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
                WorkspaceSidebarPanel.shared.prepareForTextInput()
                guard let window = nsView.window else { return }
                let currentEditor = nsView.currentEditor()
                let isAlreadyEditingThisField =
                    window.firstResponder === nsView ||
                    (currentEditor != nil && window.firstResponder === currentEditor)
                guard !isAlreadyEditingThisField else { return }
                window.makeFirstResponder(nsView)
                let insertionPoint = nsView.stringValue.count
                nsView.currentEditor()?.selectedRange = NSRange(location: insertionPoint, length: 0)
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
        if let movement = notification.userInfo?["NSTextMovement"] as? Int,
           movement == NSTextMovement.cancel.rawValue
        {
            onCancel?()
        }
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
        .contentShape(Rectangle())
        .onHover { hover in
            isHovered = hover
            TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = hover ? workspace.name : nil
        }
        .simultaneousGesture(TapGesture().onEnded {
            if !isEditing {
                focusWorkspaceFromSidebar(workspace.name)
            }
        })
        .zIndex(isDropTarget ? 1 : 0)
        .scaleEffect(isDropTarget ? 1.012 : 1)
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
        VStack(alignment: .leading, spacing: 4) {
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
            VStack(alignment: .leading, spacing: 2) {
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
                removal: .opacity,
            ))
        }
    }

    private func workspaceWindowButton(_ window: WorkspaceSidebarWindowViewModel, allowsDrag: Bool, subject: WindowDragSubject = .window) -> some View {
        Button {
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
            hoveredWindowId = hover ? window.windowId : nil
        }
        .opacity(activeSidebarDragSourceWindowId == window.windowId ? 0.38 : 1)
        .scaleEffect(activeSidebarDragSourceWindowId == window.windowId ? 0.985 : 1)
    }

    private func workspaceTabGroupView(_ group: WorkspaceSidebarTabGroupViewModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
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
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        updateSidebarWindowDrag(group.representativeWindowId, subject: .group)
                    }
                    .onEnded { _ in
                        finishSidebarWindowDrag()
                    },
            )
            .opacity(activeSidebarDragSourceWindowId == group.representativeWindowId ? 0.38 : 1)
            .scaleEffect(activeSidebarDragSourceWindowId == group.representativeWindowId ? 0.985 : 1)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(group.tabs) { tab in
                    workspaceWindowButton(tab, allowsDrag: true, subject: .window)
                        .padding(.leading, 12)
                }
            }
        }
    }

    private var sectionBackground: some View {
        sectionShape
            .fill(sectionBackgroundFill)
            .overlay {
                sectionShape
                    .strokeBorder(sectionBorderColor, lineWidth: isDropTarget ? 1.5 : 1)
            }
            .shadow(
                color: isDropTarget ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.04),
                radius: isDropTarget ? 10 : 0,
                y: isDropTarget ? 2 : 0
            )
    }

    private var header: some View {
        Group {
            if isCompact {
                workspaceBadge
                    .frame(width: 22, height: 22, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                workspaceBadge
                    .frame(width: 22, height: 22, alignment: .center)
                    .overlay(alignment: .leading) {
                        HStack(alignment: .center, spacing: 0) {
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
                                        .font(.system(size: 12, weight: workspace.isFocused ? .semibold : .medium, design: .default))
                                        .foregroundStyle(workspace.isFocused ? Color.primary : Color.secondary)
                                        .lineLimit(1)
                                }
                                if let monitorName = workspace.monitorName, !isEditing, showsWindowRows {
                                    Text(monitorName)
                                        .font(.system(size: 10, weight: .regular, design: .default))
                                        .foregroundStyle(Color.secondary.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            if isEditing {
                                HStack(spacing: 6) {
                                    Button(action: onCommitEditing) {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.accentColor)
                                    Button(action: onCancelEditing) {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.secondary)
                                }
                            } else {
                                Button(action: onBeginEditing) {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle((isHovered || workspace.isFocused) ? Color.primary : Color.secondary.opacity(0.8))
                            }
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .padding(.leading, 30) // 22 (badge) + 8 (spacing)
                    }
            }
        }
    }

    private var sectionBackgroundFill: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.16)
        } else if isHovered {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        } else if workspace.isFocused {
            return Color(nsColor: .controlBackgroundColor).opacity(0.7)
        } else if workspace.isVisible && expansionProgress > 0.5 {
            return Color(nsColor: .controlBackgroundColor).opacity(0.3)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.15)
    }

    private var sectionBorderColor: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.42)
        }
        return Color.primary.opacity(0.04)
    }

    private var workspaceBadge: some View {
        Group {
            if workspace.isGeneratedName, workspace.sidebarLabel.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            } else if workspace.isGeneratedName, let initial = workspace.displayName.first {
                Text(String(initial).uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .default))
            } else {
                Text(workspace.name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
        }
        .foregroundStyle(workspace.isFocused ? Color.white : Color.primary)
        .lineLimit(1)
        .frame(width: 22, height: 22, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(workspace.isFocused ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.1), radius: 1, y: 0.5),
        )
    }
}

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
            Button(action: onCreateWorkspace) {
                Group {
                    if isCompact {
                        ZStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 22, height: 22, alignment: .center)
                                .foregroundStyle(Color.accentColor)
                            Text("New Workspace")
                                .font(.system(size: 12, weight: .semibold, design: .default))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .frame(width: sectionWidth, alignment: isCompact ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                .background(
                    sectionShape
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(isDropTarget ? 0.34 : (isHovered ? 0.4 : 0.2)))
                        .overlay {
                            sectionShape
                                .strokeBorder(Color.accentColor.opacity(isDropTarget ? 0.42 : 0.16), lineWidth: isDropTarget ? 1.5 : 1)
                        }
                        .shadow(color: isDropTarget ? Color.accentColor.opacity(0.18) : Color.clear, radius: 10, y: 2),
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
        .zIndex(isDropTarget ? 1 : 0)
        .scaleEffect(isDropTarget ? 1.012 : 1)
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

struct WorkspaceSidebarWindowRow: View {
    let window: WorkspaceSidebarWindowViewModel
    let expansionProgress: CGFloat
    let rowHeight: CGFloat
    let isHovered: Bool
    let expandedContentWidth: CGFloat

    var body: some View {
        Image(systemName: "macwindow")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(iconForeground)
            .frame(width: 22, height: 22, alignment: .center)
            .overlay(alignment: .leading) {
                HStack(alignment: .center, spacing: 6) {
                    Text(window.title ?? window.appName)
                        .font(.system(size: 11, weight: window.isFocused ? .medium : .regular, design: .default))
                        .foregroundStyle(textForeground)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: expandedContentWidth, alignment: .leading)
                .opacity(expansionProgress)
                .padding(.leading, 30) // 22 + 8
            }
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(backgroundFill)
            )
            .contentShape(Rectangle())
    }

    private var backgroundFill: Color {
        guard expansionProgress > 0.5 else { return Color.clear }
        if window.isFocused {
            return Color(nsColor: .controlBackgroundColor).opacity(0.8)
        } else if isHovered {
            return Color(nsColor: .controlBackgroundColor).opacity(0.4)
        }
        return Color.clear
    }

    private var textForeground: Color {
        window.isFocused ? Color.primary : Color.secondary
    }

    private var iconForeground: Color {
        window.isFocused ? Color.primary : Color.secondary.opacity(0.5)
    }
}

struct WorkspaceSidebarTabGroupRow: View {
    let group: WorkspaceSidebarTabGroupViewModel
    let expansionProgress: CGFloat
    let rowHeight: CGFloat
    let expandedContentWidth: CGFloat

    var body: some View {
        Image(systemName: "square.stack.3d.up.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(iconForeground)
            .frame(width: 22, height: 22, alignment: .center)
            .overlay(alignment: .leading) {
                HStack(alignment: .center, spacing: 6) {
                    Text(groupLabel)
                        .font(.system(size: 11, weight: group.isFocused ? .semibold : .medium, design: .default))
                        .foregroundStyle(textForeground)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: expandedContentWidth, alignment: .leading)
                .opacity(expansionProgress)
                .padding(.leading, 30)
            }
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(backgroundFill)
            )
            .contentShape(Rectangle())
    }

    private var groupLabel: String {
        let title = group.title.isEmpty ? "Tab Group" : group.title
        return "\(title) • \(group.windowCount)"
    }

    private var backgroundFill: Color {
        if group.isFocused {
            return Color.accentColor.opacity(0.12)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.3)
    }

    private var textForeground: Color {
        group.isFocused ? Color.primary : Color.secondary
    }

    private var iconForeground: Color {
        group.isFocused ? Color.accentColor : Color.secondary.opacity(0.7)
    }
}

private struct WorkspaceSidebarOptionalDragModifier: ViewModifier {
    let isEnabled: Bool
    let onChanged: () -> Void
    let onEnded: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in onChanged() }
                    .onEnded { _ in onEnded() },
            )
        } else {
            content
        }
    }
}

struct WorkspaceSidebarPreviewRow: View {
    let preview: WorkspaceSidebarDropPreviewViewModel
    let expansionProgress: CGFloat
    let rowHeight: CGFloat
    let expandedContentWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: preview.isTabGroup ? "square.stack.3d.up.fill" : "macwindow")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22, alignment: .center)
                .overlay(alignment: .leading) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(previewLabel)
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(width: expandedContentWidth, alignment: .leading)
                    .opacity(expansionProgress)
                    .padding(.leading, 30)
                }
        }
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.accentColor.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                }
        )
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }

    private var previewLabel: String {
        if preview.isTabGroup {
            return preview.label
        }
        return preview.label
    }
}
