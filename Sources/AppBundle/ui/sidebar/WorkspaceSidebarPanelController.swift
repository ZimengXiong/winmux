import AppKit
import Common
import SwiftUI

@MainActor
final class WorkspaceSidebarPanel: NSPanelHud {
    static let shared = WorkspaceSidebarPanel(monitor: mainMonitor)
    private static var panelsByMonitorScopeId: [String: WorkspaceSidebarPanel] = [:]
    static weak var activeInlineTextEditingPanel: WorkspaceSidebarPanel?

    let viewModel: TrayMenuModel
    let hostingView: WorkspaceSidebarHostingView
    let monitorScopeId: String
    var pendingExpand: DispatchWorkItem?
    var pendingCollapse: DispatchWorkItem?
    var pendingCollapseFinalize: DispatchWorkItem?
    var lastHoverMonitorTimestamp: CFTimeInterval = 0
    var hasPendingHoverRecheck = false
    var menuTrackingDepth = 0
    var menuTrackingGraceUntil: Date = .distantPast
    var inlineTextEditingActive = false
    var inlineTextEditingLocksExpansion = true
    var inlineTextEditingCancelsOnPointerExit = true
    var inlineTextEditingCancel: (@MainActor () -> Void)?
    var inlineTextEditingKeyDown: (@MainActor (WorkspaceSidebarInlineTextKey) -> Void)?
    var inlineTextEditingEventMonitors: [Any] = []
    var inlineTextEditingKeyEventTap: CFMachPort?
    var inlineTextEditingKeyEventTapRunLoopSource: CFRunLoopSource?
    var inlineTextEditingStartedAt: Date = .distantPast
    var inlineTextEditingPointerEnteredVisibleRegion = false
    var commandExpansionLocksCollapse = false
    var shouldLockNextSidebarSearchExpansion = false
    var bufferedCommandSidebarSearchKeys: [WorkspaceSidebarInlineTextKey] = []
    var commandMouseUnlockPoint: CGPoint?
    var commandMouseUnlockMonitors: [Any] = []
    var menuTrackingObservers: [NSObjectProtocol] = []
    var lastEdgeTrapSample: MousePointerSample?
    var edgeTrapStartedAt: TimeInterval?
    var edgeTrapSuppressedUntil: TimeInterval = 0
    var splitBrowseCollapseSuppressedUntil: Date = .distantPast
    var persistentExpansionWidth: CGFloat?
    let hoverExitTolerance: CGFloat = 20
    let hoverPollInterval: TimeInterval = 1.0 / 30.0
    let hoverOpenDelay: TimeInterval = 0.05
    let hoverCueAnimationResponse: TimeInterval = 0.18
    let animationDuration: TimeInterval = 0.14
    let menuTrackingEndGrace: TimeInterval = 0.75
    let edgeTrapBandWidth: CGFloat = 18
    let edgeTrapReleaseVelocityThreshold: CGFloat = 4
    let edgeTrapReleaseDelay: TimeInterval = 0.2
    let edgeTrapCrossingGrace: TimeInterval = 0.25

    private init(monitor: Monitor) {
        monitorScopeId = workspaceSidebarMonitorScopeId(for: monitor)
        viewModel = TrayMenuModel()
        hostingView = WorkspaceSidebarHostingView(rootView: WorkspaceSidebarContainerView(
            viewModel: viewModel,
            actions: makeWorkspaceSidebarActionsAdapter(viewModel: viewModel, targetMonitorScopeId: monitorScopeId)
        ))
        super.init()
        identifier = NSUserInterfaceItemIdentifier("\(workspaceSidebarPanelId).\(monitorScopeId)")
        styleMask.remove(.nonactivatingPanel)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        applyWorkspaceSidebarLayer(stayOnTop: config.workspaceSidebar.stayOnTop)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        installMenuTrackingObservers()
    }

    static var visiblePanels: [WorkspaceSidebarPanel] {
        panelsByMonitorScopeId.values.filter(\.isVisible)
    }

    static func panel(containing point: CGPoint) -> WorkspaceSidebarPanel? {
        visiblePanels.first { $0.visibleScreenRectNormalized()?.contains(point) == true }
    }

    static func panel(for monitorScopeId: String) -> WorkspaceSidebarPanel? {
        panelsByMonitorScopeId[monitorScopeId]
    }

    static func updateVisibleDropTargets(_ targets: [WorkspaceSidebarDropTargetFrame]) {
        workspaceSidebarDropTargets = visiblePanels.flatMap { $0.convertDropTargets(targets) }
    }

    static func refreshAll() {
        let activeMonitorScopeIds = Set(workspaceSidebarResolvedPanelMonitors().map { workspaceSidebarMonitorScopeId(for: $0) })
        for monitor in workspaceSidebarResolvedPanelMonitors() {
            let scopeId = workspaceSidebarMonitorScopeId(for: monitor)
            let panel = panelsByMonitorScopeId[scopeId] ?? WorkspaceSidebarPanel(monitor: monitor)
            panelsByMonitorScopeId[scopeId] = panel
            panel.syncModelFromShared()
            panel.refresh(on: monitor)
        }
        for (scopeId, panel) in panelsByMonitorScopeId where !activeMonitorScopeIds.contains(scopeId) {
            panel.resetHiddenSidebarState()
        }
    }

    static func syncVisiblePanelModelsFromShared() {
        for panel in panelsByMonitorScopeId.values {
            panel.syncModelFromShared()
        }
    }

    func syncModelFromShared() {
        // Equality-guarded: this runs several times per refresh session, and each unguarded
        // @Published write would invalidate the whole sidebar SwiftUI tree even when nothing
        // changed. workspaceSidebarVisibleWidth/isWorkspaceSidebarExpanded are panel-local and
        // never synced. experimentalUISettings is stateless (reads UserDefaults live) and only
        // the menu bar label observes it, so it isn't synced either.
        viewModel.setIfChanged(\.trayText, TrayMenuModel.shared.trayText)
        viewModel.setIfChanged(\.trayItems, TrayMenuModel.shared.trayItems)
        viewModel.setIfChanged(\.isEnabled, TrayMenuModel.shared.isEnabled)
        viewModel.setIfChanged(\.workspaces, TrayMenuModel.shared.workspaces)
        viewModel.setIfChanged(\.workspaceSidebarWorkspaces, TrayMenuModel.shared.workspaceSidebarWorkspaces)
        viewModel.setIfChanged(\.workspaceSidebarProjects, TrayMenuModel.shared.workspaceSidebarProjects)
        viewModel.setIfChanged(\.workspaceSidebarActiveProjectId, resolvedLocalActiveProjectId())
        viewModel.setIfChanged(\.workspaceSidebarMonitorScopes, TrayMenuModel.shared.workspaceSidebarMonitorScopes)
        viewModel.setIfChanged(\.workspaceSidebarSelectedMonitorScopeId, resolvedLocalSelectedMonitorScopeId())
        viewModel.setIfChanged(\.workspaceSidebarTargetMonitorScopeId, monitorScopeId)
        viewModel.setIfChanged(\.workspaceSidebarFocusedMonitorScopeId, TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId)
        viewModel.setIfChanged(\.workspaceSidebarShowsMonitorSelector, TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector)
        viewModel.setIfChanged(\.workspaceSidebarDropPreview, TrayMenuModel.shared.workspaceSidebarDropPreview)
        viewModel.setIfChanged(\.windowTabStrips, TrayMenuModel.shared.windowTabStrips)
        viewModel.setIfChanged(\.workspaceSidebarTopPadding, TrayMenuModel.shared.workspaceSidebarTopPadding)
        viewModel.setIfChanged(\.workspaceSidebarHoveredWorkspaceName, resolvedLocalHoveredWorkspaceName())
    }

    private func resolvedLocalActiveProjectId() -> WorkspaceProjectId {
        let monitor = workspaceSidebarMonitor(forScopeId: monitorScopeId)
        return monitor.map { activeWorkspaceProjectId(for: $0) } ?? workspaceProjectDefaultId
    }

    private func resolvedLocalSelectedMonitorScopeId() -> String {
        let validScopeIds = Set(TrayMenuModel.shared.workspaceSidebarMonitorScopes.map(\.id))
        if validScopeIds.contains(viewModel.workspaceSidebarSelectedMonitorScopeId) {
            return viewModel.workspaceSidebarSelectedMonitorScopeId
        }
        return workspaceSidebarDefaultScopeId
    }

    private func resolvedLocalHoveredWorkspaceName() -> String? {
        let visibleWorkspaceNames = visibleWorkspaceNamesForSidebar(
            workspaces: TrayMenuModel.shared.workspaceSidebarWorkspaces,
            selectedMonitorScopeId: viewModel.workspaceSidebarSelectedMonitorScopeId,
            focusedMonitorScopeId: TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId,
        )
        return sanitizedWorkspaceSidebarHoveredWorkspaceName(
            visibleWorkspaceNames: visibleWorkspaceNames,
            hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        debugWorkspaceSidebarRenameLog("panel becomeKey isKey=\(isKeyWindow) firstResponder=\(String(describing: firstResponder))")
    }

    override func resignKey() {
        debugWorkspaceSidebarRenameLog("panel resignKey isKey=\(isKeyWindow) firstResponder=\(String(describing: firstResponder))")
        super.resignKey()
    }

    override func keyDown(with event: NSEvent) {
        debugWorkspaceSidebarRenameLog("panel keyDown keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "nil") firstResponder=\(String(describing: firstResponder)) inline=\(inlineTextEditingActive)")
        if handleInlineTextEditingKey(inlineTextKey(from: event)) {
            return
        }
        super.keyDown(with: event)
    }
}

final class WorkspaceSidebarHostingView: NSHostingView<WorkspaceSidebarContainerView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
