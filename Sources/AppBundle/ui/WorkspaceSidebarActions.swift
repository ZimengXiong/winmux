import AppKit
import Common
import SwiftUI

@MainActor
func focusWorkspaceFromSidebar(_ workspaceName: String) {
    runWorkspaceSidebarSession {
        _ = Workspace.existing(byName: workspaceName)?.focusWorkspace()
    }
}

@MainActor
func runWorkspaceSidebarSession(_ body: @escaping @MainActor () async throws -> Void) {
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
func showWorkspaceSidebarError(_ body: String) {
    MessageModel.shared.message = Message(
        description: "Workspace Sidebar Error",
        body: body,
    )
}

@MainActor
func promptWorkspaceSidebarName(title: String, currentName: String) -> String? {
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
func sidebarWorkspaceTargetMonitor(fallbackWindow: Window? = nil, fallbackPoint: CGPoint? = nil) -> Monitor {
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
func selectedWorkspaceSidebarMonitorScope() -> Monitor? {
    let selectedScopeId = TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId
    guard selectedScopeId != workspaceSidebarFocusedScopeId,
          selectedScopeId != workspaceSidebarAllScopeId
    else {
        return nil
    }
    return sortedMonitors.first { workspaceSidebarMonitorScopeId(for: $0) == selectedScopeId }
}

@MainActor
func selectWorkspaceSidebarMonitorScope(_ scopeId: String) {
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
func createWorkspaceFromSidebarButton() {
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
func sidebarWorkspaceTargetProjectId(targetMonitor: Monitor) -> WorkspaceProjectId {
    let selectedProjectId = TrayMenuModel.shared.workspaceSidebarSelectedProjectId
    guard workspaceProjects().contains(where: { $0.id == selectedProjectId }) else {
        return activeWorkspaceProjectId(for: targetMonitor)
    }
    return selectedProjectId
}

@MainActor
func selectWorkspaceSidebarProject(_ projectId: WorkspaceProjectId) {
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
func createWorkspaceSidebarProject() {
    runWorkspaceSidebarSession {
        let project = createWorkspaceProject()
        TrayMenuModel.shared.workspaceSidebarSelectedProjectId = project.id
        if let workspace = switchWorkspaceProject(project.id, on: sidebarWorkspaceTargetMonitor()) {
            _ = workspace.focusWorkspace()
        }
    }
}

@MainActor
func renameWorkspaceSidebarProject(_ project: WorkspaceSidebarProjectViewModel, displayName: String) {
    runWorkspaceSidebarSession {
        try renameWorkspaceProject(project.id, displayName: displayName)
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
func setWorkspaceSidebarProjectColor(_ project: WorkspaceSidebarProjectViewModel, colorHex: String?) {
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
func deleteWorkspaceSidebarProject(_ project: WorkspaceSidebarProjectViewModel) {
    guard canDeleteWorkspaceProject(project.id) else { return }
    guard confirmWorkspaceSidebarProjectDeletion(project) else { return }
    let fallbackProjectId = workspaceProjectFallbackForDeletion(excluding: project.id)
    runWorkspaceSidebarSession {
        try await deleteWorkspaceProjectFromSidebar(project.id)
        TrayMenuModel.shared.workspaceSidebarSelectedProjectId = fallbackProjectId
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
private func confirmWorkspaceSidebarProjectDeletion(_ project: WorkspaceSidebarProjectViewModel) -> Bool {
    let windowCount = windowsInWorkspaceProject(project.id).count
    guard windowCount > 0 else { return true }

    let alert = NSAlert()
    switch config.workspaceSidebar.projectDeletionAction {
        case .closeWindows:
            alert.messageText = "Close Project Windows?"
            alert.informativeText = """
            WinMux will ask macOS to close \(windowCount) window\(windowCount == 1 ? "" : "s") in “\(project.displayName)”. Apps may show their own confirmation dialogs for unsaved work. If any window stays open, WinMux will keep the project.
            """
            alert.addButton(withTitle: "Close Project")
        case .moveWindowsToFallback:
            alert.messageText = "Delete Project?"
            alert.informativeText = """
            WinMux will delete “\(project.displayName)” and move \(windowCount) window\(windowCount == 1 ? "" : "s") to another project.
            """
            alert.addButton(withTitle: "Delete Project")
    }
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning
    return alert.runModal() == .alertFirstButtonReturn
}

@MainActor
func renameWorkspaceFromSidebar(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
    guard let newName = promptWorkspaceSidebarName(title: "Rename Workspace", currentName: workspace.displayName) else { return }
    renameWorkspaceFromSidebar(workspace, displayName: newName)
}

@MainActor
func renameWorkspaceFromSidebar(_ workspace: WorkspaceSidebarWorkspaceViewModel, displayName: String) {
    runWorkspaceSidebarSession {
        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: displayName)
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
func resetWorkspaceNameFromSidebar(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
    runWorkspaceSidebarSession {
        try resetWorkspaceSidebarName(workspaceName: workspace.name)
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
func deleteWorkspaceFromSidebar(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
    runWorkspaceSidebarSession {
        try deleteWorkspaceForSidebar(workspaceName: workspace.name)
        await updateWorkspaceSidebarModel()
    }
}

@MainActor
func focusWindowFromSidebar(_ windowId: UInt32, fallbackWorkspace: String) {
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
func updateSidebarWindowDrag(_ windowId: UInt32, subject: WindowDragSubject = .window) {
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
func finishSidebarWindowDrag() {
    Task { @MainActor in
        try? await resetManipulatedWithMouseIfPossible()
    }
}
