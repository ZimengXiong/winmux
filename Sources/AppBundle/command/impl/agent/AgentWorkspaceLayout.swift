import Common
import Foundation

struct AgentWorkspaceLayout: Codable {
    let name: String
    let focusPane: AgentPaneRef?
    let layout: AgentLayoutNode
    let floating: [AgentPaneRef]?

    private enum CodingKeys: String, CodingKey {
        case name
        case focusPane = "focus"
        case layout
        case floating
    }

    @MainActor
    func validate(appendTo errors: inout [String]) async throws {
        var orderedWindowIds: [UInt32] = []
        layout.collectWindowIds(result: &orderedWindowIds)
        for ref in floating ?? [] {
            ref.resolveNode()?.allLeafWindowsRecursive.forEach { orderedWindowIds.append($0.windowId) }
        }

        let windowIds = Set(orderedWindowIds)
        for windowId in duplicateAgentWindowIds(in: orderedWindowIds) {
            errors.append("setWorkspaceLayout '\(name)': window \(windowId) appears more than once")
        }
        for windowId in windowIds where Window.get(byId: windowId) == nil {
            errors.append("setWorkspaceLayout '\(name)': window \(windowId) does not exist")
        }
        for ref in floating ?? [] where ref.resolveNode() == nil {
            errors.append("setWorkspaceLayout '\(name)': floating pane does not exist")
        }
    }

    @MainActor
    func apply() async throws {
        let existedBefore = Workspace.existing(byName: name) != nil
        let workspace = Workspace.get(byName: name)
        if !existedBefore {
            workspace.assignProject(focus.workspace.projectId)
        }
        workspace.seedMonitorIfNeeded(focusPane?.resolveNode()?.nodeMonitor ?? focus.workspace.workspaceMonitor)
        let oldWindows = workspace.allLeafWindowsRecursive
        var referenced: Set<UInt32> = []
        layout.collectWindowIds(result: &referenced)
        for ref in floating ?? [] {
            ref.resolveNode()?.allLeafWindowsRecursive.forEach { referenced.insert($0.windowId) }
        }

        workspace.rootTilingContainer.unbindFromParent()
        switch layout {
            case .split:
                _ = try await layout.bind(into: workspace, index: INDEX_BIND_LAST)
            case .window, .tabGroup:
                _ = try await layout.bind(into: workspace.rootTilingContainer, index: INDEX_BIND_LAST)
        }
        bindFloatingPanes(to: workspace)
        restoreUnreferencedWindows(oldWindows, referenced: referenced, root: workspace.rootTilingContainer)
        layout.applySizeRatios(to: workspace.rootTilingContainer)
        if let focusNode = focusPane?.resolveNode() {
            _ = focusNode.mostRecentWindowRecursive?.focusWindow()
        }
    }

    @MainActor
    private func bindFloatingPanes(to workspace: Workspace) {
        for ref in floating ?? [] {
            if let node = ref.resolveNode(), let window = node as? Window {
                window.bindAsFloatingWindow(to: workspace)
            }
        }
    }

    @MainActor
    private func restoreUnreferencedWindows(_ oldWindows: [Window], referenced: Set<UInt32>, root: TilingContainer) {
        for window in oldWindows where !referenced.contains(window.windowId) && window.isBound {
            if window.nodeWorkspace == nil || window.nodeWorkspace == root.nodeWorkspace {
                window.bind(to: root, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            }
        }
    }
}
