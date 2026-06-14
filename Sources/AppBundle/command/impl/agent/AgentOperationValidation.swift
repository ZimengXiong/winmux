import Foundation

extension AgentOperation {
    @MainActor
    func validate(context: inout AgentValidationContext, appendTo errors: inout [String]) async throws {
        switch self {
            case .focusWindow(let target):
                if try await target.resolveWindow() == nil { errors.append("focusWindow: no matching window") }
            case .focusWorkspace(let workspace):
                if Workspace.existing(byName: workspace) == nil { errors.append("focusWorkspace: workspace '\(workspace)' does not exist") }
            case .moveWindowToWorkspace(let windowId, _, _),
                 .setWinMuxFullscreen(let windowId, _, _),
                 .setFloating(let windowId, _),
                 .closeWindow(let windowId, _),
                 .moveWindowOutOfTabGroup(let windowId):
                if Window.get(byId: windowId) == nil { errors.append("Window \(windowId) does not exist") }
            case .moveTabGroupToWorkspace(let tabGroupId, _, _):
                if resolveAgentTabGroup(tabGroupId) == nil, context.plannedTabGroups[tabGroupId] == nil {
                    errors.append("Tab group '\(tabGroupId)' does not exist")
                }
            case .swapPanes(let a, let b):
                if !a.canResolve(in: context) { errors.append("swapPanes: first pane does not exist") }
                if !b.canResolve(in: context) { errors.append("swapPanes: second pane does not exist") }
            case .placePane(let pane, _, let target):
                if !pane.canResolve(in: context) { errors.append("placePane: source pane does not exist") }
                if !target.canResolve(in: context) { errors.append("placePane: target pane does not exist") }
            case .createTabGroup(let tabGroupId, let workspace, let tabs, let activeWindowId):
                validateCreateTabGroup(tabGroupId, workspace: workspace, tabs: tabs, activeWindowId: activeWindowId, context: &context, errors: &errors)
            case .addWindowToTabGroup(let windowId, let tabGroupId, let activeWindowId):
                validateAddWindowToTabGroup(windowId, tabGroupId: tabGroupId, activeWindowId: activeWindowId, context: context, errors: &errors)
            case .setActiveTab(let tabGroupId, let windowId):
                validateSetActiveTab(tabGroupId, windowId: windowId, context: context, errors: &errors)
            case .parkWindow(let pane, _):
                if !pane.canResolve(in: context) { errors.append("parkWindow: pane does not exist") }
            case .setPaneSize(let pane, let axis, _):
                validateSetPaneSize(pane, axis: axis, context: context, errors: &errors)
            case .setWorkspaceLayout(let layout):
                try await layout.validate(appendTo: &errors)
        }
    }

    @MainActor
    private func validateCreateTabGroup(
        _ tabGroupId: String?,
        workspace: String?,
        tabs: [UInt32],
        activeWindowId: UInt32?,
        context: inout AgentValidationContext,
        errors: inout [String],
    ) {
        if tabs.count < 2 { errors.append("createTabGroup requires at least two tabs") }
        for id in duplicateAgentWindowIds(in: tabs) {
            errors.append("createTabGroup: window \(id) appears more than once")
        }
        for id in tabs where Window.get(byId: id) == nil { errors.append("createTabGroup: window \(id) does not exist") }
        if let activeWindowId, !tabs.contains(activeWindowId) { errors.append("createTabGroup: activeWindowId must be in tabs") }
        if workspace == nil, Window.get(byId: tabs.first ?? 0)?.nodeWorkspace == nil {
            errors.append("createTabGroup: workspace is required when the first tab has no workspace")
        }
        if let tabGroupId {
            context.plannedTabGroups[tabGroupId] = Set(tabs)
        }
    }

    @MainActor
    private func validateAddWindowToTabGroup(
        _ windowId: UInt32,
        tabGroupId: String,
        activeWindowId: UInt32?,
        context: AgentValidationContext,
        errors: inout [String],
    ) {
        if Window.get(byId: windowId) == nil { errors.append("addWindowToTabGroup: window \(windowId) does not exist") }
        if let activeWindowId, Window.get(byId: activeWindowId) == nil { errors.append("addWindowToTabGroup: active window \(activeWindowId) does not exist") }
        if resolveAgentTabGroup(tabGroupId) == nil, context.plannedTabGroups[tabGroupId] == nil {
            errors.append("addWindowToTabGroup: tab group '\(tabGroupId)' does not exist")
        }
    }

    @MainActor
    private func validateSetActiveTab(
        _ tabGroupId: String,
        windowId: UInt32,
        context: AgentValidationContext,
        errors: inout [String],
    ) {
        let isExistingTab = resolveAgentTabGroup(tabGroupId)?.agentTabWindows.contains(where: { $0.windowId == windowId }) == true
        let isPlannedTab = context.plannedTabGroups[tabGroupId]?.contains(windowId) == true
        if !isExistingTab && !isPlannedTab {
            errors.append("setActiveTab: window \(windowId) is not in tab group '\(tabGroupId)'")
        }
    }

    @MainActor
    private func validateSetPaneSize(
        _ pane: AgentPaneRef,
        axis: AgentLayoutDirection?,
        context: AgentValidationContext,
        errors: inout [String],
    ) {
        guard let node = pane.resolveNode() else {
            if pane.canResolve(in: context) { return }
            errors.append("setPaneSize: pane does not exist")
            return
        }
        if agentResizableNode(for: node, axis: axis) == nil {
            if let axis {
                errors.append("setPaneSize: pane is not inside a \(axis.rawValue) tiled split")
            } else {
                errors.append("setPaneSize: pane is not inside a tiled split")
            }
        }
    }
}
