import CoreGraphics
import Foundation
import AppKit

@MainActor
func openWorkspaceSidebarFromCommand() {
    guard TrayMenuModel.shared.isEnabled, config.workspaceSidebar.enabled else { return }
    let originalMouseLocation = mouseLocation
    WorkspaceSidebarPanel.refreshAll()
    let focusedScopeId = TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId
    let panel = WorkspaceSidebarPanel.panel(for: focusedScopeId)
        ?? WorkspaceSidebarPanel.visiblePanels.first
        ?? WorkspaceSidebarPanel.shared
    if panel.viewModel.isWorkspaceSidebarExpanded || panel.inlineTextEditingActive {
        closeWorkspaceSidebarFromCommand(panel)
        return
    }
    panel.expandSidebar(to: CGFloat(config.workspaceSidebar.width))
    guard let parkedPoint = workspaceSidebarCommandMouseParkPoint(for: panel) else { return }
    panel.commandParkedMousePoint = parkedPoint
    panel.commandOriginalMousePoint = originalMouseLocation
    panel.commandMouseRestoreAllowed = true
    moveWorkspaceSidebarCommandMouse(to: parkedPoint)
    installWorkspaceSidebarCommandMouseMoveMonitor(panel)
}

@MainActor
func closeWorkspaceSidebarFromCommand(_ panel: WorkspaceSidebarPanel) {
    panel.endInlineTextEditing()
    panel.pendingExpand?.cancel()
    panel.pendingExpand = nil
    panel.pendingCollapse?.cancel()
    panel.pendingCollapse = nil
    panel.pendingCollapseFinalize?.cancel()
    panel.pendingCollapseFinalize = nil
    NotificationCenter.default.post(name: workspaceSidebarWillCollapseNotification, object: panel)
    panel.animateVisibleSidebarWidth(CGFloat(config.workspaceSidebar.collapsedWidth), animation: .easeInOut(duration: panel.animationDuration))
    panel.viewModel.isWorkspaceSidebarExpanded = false
    panel.updateMousePassthrough()
    restoreWorkspaceSidebarCommandMouseIfUnmoved(panel)
}

@MainActor
private func workspaceSidebarCommandMouseParkPoint(for panel: WorkspaceSidebarPanel) -> CGPoint? {
    guard let visibleRect = panel.visibleScreenRectNormalized() else { return nil }
    return CGPoint(
        x: visibleRect.minX + min(max(panel.viewModel.workspaceSidebarVisibleWidth * 0.5, 18), max(visibleRect.width - 12, 18)),
        y: visibleRect.center.y,
    )
}

private func moveWorkspaceSidebarCommandMouse(to point: CGPoint) {
    let event = CGEvent(
        mouseEventSource: nil,
        mouseType: CGEventType.mouseMoved,
        mouseCursorPosition: point,
        mouseButton: CGMouseButton.left,
    )
    event?.post(tap: .cghidEventTap)
}

@MainActor
func restoreWorkspaceSidebarCommandMouseIfUnmoved(_ panel: WorkspaceSidebarPanel) {
    guard panel.commandParkedMousePoint != nil,
          let originalPoint = panel.commandOriginalMousePoint
    else { return }
    panel.commandParkedMousePoint = nil
    panel.commandOriginalMousePoint = nil
    removeWorkspaceSidebarCommandMouseMoveMonitor(panel)
    guard panel.commandMouseRestoreAllowed else { return }
    panel.commandMouseRestoreAllowed = false
    moveWorkspaceSidebarCommandMouse(to: originalPoint)
}

@MainActor
private func installWorkspaceSidebarCommandMouseMoveMonitor(_ panel: WorkspaceSidebarPanel) {
    removeWorkspaceSidebarCommandMouseMoveMonitor(panel)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak panel] in
        guard let panel, panel.commandOriginalMousePoint != nil else { return }
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak panel] event in
            panel?.commandMouseRestoreAllowed = false
            return event
        }
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak panel] _ in
            Task { @MainActor in
                panel?.commandMouseRestoreAllowed = false
            }
        }
        panel.commandMouseMoveMonitors = [localMonitor, globalMonitor].compactMap { $0 }
    }
}

@MainActor
private func removeWorkspaceSidebarCommandMouseMoveMonitor(_ panel: WorkspaceSidebarPanel) {
    for monitor in panel.commandMouseMoveMonitors {
        NSEvent.removeMonitor(monitor)
    }
    panel.commandMouseMoveMonitors = []
}
