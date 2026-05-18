import AppKit
import Common
import SwiftUI

@MainActor
final class WorkspaceSidebarPanel: NSPanelHud {
    static let shared = WorkspaceSidebarPanel()

    let hostingView = NSHostingView(rootView: WorkspaceSidebarContainerView(
        viewModel: TrayMenuModel.shared,
        actions: makeWorkspaceSidebarActionsAdapter()
    ))
    var pendingExpand: DispatchWorkItem?
    var pendingCollapse: DispatchWorkItem?
    var pendingCollapseFinalize: DispatchWorkItem?
    var isHoverMonitoring = false
    var lastHoverMonitorTimestamp: CFTimeInterval = 0
    var menuTrackingDepth = 0
    var inlineTextEditingActive = false
    var menuTrackingObservers: [NSObjectProtocol] = []
    let hoverExitTolerance: CGFloat = 20
    let hoverPollInterval: TimeInterval = 1.0 / 30.0
    let hoverOpenDelay: TimeInterval = 0.05
    let hoverCueAnimationResponse: TimeInterval = 0.18
    let animationDuration: TimeInterval = 0.14

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
}
