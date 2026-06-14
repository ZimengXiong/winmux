import Common
import Foundation

extension AgentOperation {
    @MainActor
    func apply(context: inout AgentApplyContext) async throws {
        switch self {
            case .focusWindow(let target):
                _ = try await target.resolveWindow()?.focusWindow()
            case .focusWorkspace(let workspace):
                _ = Workspace.existing(byName: workspace)?.focusWorkspace()
            case .moveWindowToWorkspace(let windowId, let workspace, let shouldFocus):
                applyMoveWindowToWorkspace(windowId, workspace: workspace, shouldFocus: shouldFocus)
            case .moveTabGroupToWorkspace(let tabGroupId, let workspace, let shouldFocus):
                applyMoveTabGroupToWorkspace(tabGroupId, workspace: workspace, shouldFocus: shouldFocus, context: context)
            case .swapPanes(let a, let b):
                guard let nodeA = a.resolveNode(context: context), let nodeB = b.resolveNode(context: context) else { return }
                swapNodes(nodeA, nodeB)
            case .placePane(let pane, let relation, let target):
                guard let source = pane.resolveNode(context: context), let target = target.resolveNode(context: context) else { return }
                placeAgentPane(source, relation: relation, target: target)
            case .createTabGroup(let tabGroupId, let workspace, let tabs, let activeWindowId):
                applyCreateTabGroup(tabGroupId, workspace: workspace, tabs: tabs, activeWindowId: activeWindowId, context: &context)
            case .addWindowToTabGroup(let windowId, let tabGroupId, let activeWindowId):
                applyAddWindowToTabGroup(windowId, tabGroupId: tabGroupId, activeWindowId: activeWindowId, context: context)
            case .moveWindowOutOfTabGroup(let windowId):
                guard let window = Window.get(byId: windowId) else { return }
                _ = removeWindowFromTabStack(window)
            case .setActiveTab(let tabGroupId, let windowId):
                applySetActiveTab(tabGroupId, windowId: windowId, context: context)
            case .setWinMuxFullscreen(let windowId, let value, let noOuterGaps):
                guard let window = Window.get(byId: windowId) else { return }
                window.isFullscreen = value
                window.noOuterGapsInFullscreen = noOuterGaps ?? window.noOuterGapsInFullscreen
                window.markAsMostRecentChild()
            case .setFloating(let windowId, let value):
                applySetFloating(windowId, value: value)
            case .closeWindow(let windowId, let quitAppIfLastWindow):
                try await applyCloseWindow(windowId, quitAppIfLastWindow: quitAppIfLastWindow)
            case .parkWindow(let pane, let workspace):
                applyParkWindow(pane, workspace: workspace, context: context)
            case .setPaneSize(let pane, let axis, let size):
                guard let node = pane.resolveNode(context: context) else { return }
                setAgentPaneSize(node, axis: axis, size: size)
            case .setWorkspaceLayout(let layout):
                try await layout.apply()
        }
    }

    @MainActor
    private func applyMoveWindowToWorkspace(_ windowId: UInt32, workspace: String, shouldFocus: Bool?) {
        guard let window = Window.get(byId: windowId) else { return }
        let targetWorkspace = getAgentTargetWorkspace(named: workspace, projectSource: window.nodeWorkspace, monitorSource: window)
        _ = agentMoveWindowToWorkspace(window, targetWorkspace, focusFollowsWindow: shouldFocus ?? false)
    }

    @MainActor
    private func applyMoveTabGroupToWorkspace(
        _ tabGroupId: String,
        workspace: String,
        shouldFocus: Bool?,
        context: AgentApplyContext,
    ) {
        guard let group = resolveAgentTabGroup(tabGroupId, context: context) else { return }
        let targetWorkspace = getAgentTargetWorkspace(named: workspace, projectSource: group.nodeWorkspace, monitorSource: group)
        let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
        group.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
        if shouldFocus ?? false { _ = group.mostRecentWindowRecursive?.focusWindow() }
    }

    @MainActor
    private func applyCreateTabGroup(
        _ tabGroupId: String?,
        workspace: String?,
        tabs: [UInt32],
        activeWindowId: UInt32?,
        context: inout AgentApplyContext,
    ) {
        let windows = tabs.compactMap { Window.get(byId: $0) }
        guard let first = windows.first else { return }
        let workspaceName = workspace ?? first.nodeWorkspace?.name ?? focus.workspace.name
        let targetWorkspace = getAgentTargetWorkspace(named: workspaceName, projectSource: first.nodeWorkspace, monitorSource: first)
        for window in windows where window.nodeWorkspace != targetWorkspace {
            _ = agentMoveWindowToWorkspace(window, targetWorkspace, focusFollowsWindow: false)
        }
        for window in windows.dropFirst() {
            createOrAppendWindowTabStack(sourceWindow: window, onto: first)
        }
        if let group = first.nearestWindowTabGroup {
            reorderAgentTabGroup(group, tabs: tabs)
            if let tabGroupId {
                context.tabGroupAliases[tabGroupId] = group
            }
        }
        if let activeWindowId {
            Window.get(byId: activeWindowId)?.markAsMostRecentChild()
            _ = Window.get(byId: activeWindowId)?.focusWindow()
        }
    }

    @MainActor
    private func applyAddWindowToTabGroup(
        _ windowId: UInt32,
        tabGroupId: String,
        activeWindowId: UInt32?,
        context: AgentApplyContext,
    ) {
        guard let window = Window.get(byId: windowId),
              let group = resolveAgentTabGroup(tabGroupId, context: context),
              let target = group.agentTabWindows.first
        else { return }
        createOrAppendWindowTabStack(sourceWindow: window, onto: target)
        if let activeWindowId {
            Window.get(byId: activeWindowId)?.markAsMostRecentChild()
            _ = Window.get(byId: activeWindowId)?.focusWindow()
        }
    }

    @MainActor
    private func applySetActiveTab(_ tabGroupId: String, windowId: UInt32, context: AgentApplyContext) {
        guard let window = Window.get(byId: windowId),
              resolveAgentTabGroup(tabGroupId, context: context)?.agentTabWindows.contains(where: { $0 == window }) == true
        else { return }
        window.markAsMostRecentChild()
        _ = window.focusWindow()
    }

    @MainActor
    private func applySetFloating(_ windowId: UInt32, value: Bool) {
        guard let window = Window.get(byId: windowId), let workspace = window.nodeWorkspace else { return }
        if value {
            window.bindAsFloatingWindow(to: workspace)
        } else if window.isFloating {
            let binding = workspaceAppendBindingData(targetWorkspace: workspace, index: INDEX_BIND_LAST)
            window.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
        }
    }

    @MainActor
    private func applyCloseWindow(_ windowId: UInt32, quitAppIfLastWindow: Bool?) async throws {
        if quitAppIfLastWindow ?? false {
            var args = CloseCmdArgs(rawArgs: [])
            args.windowId = windowId
            args.quitIfLastWindow = true
            _ = try await CloseCommand(args: args).run(.defaultEnv, .emptyStdin)
        } else {
            Window.get(byId: windowId)?.closeAxWindow()
        }
    }

    @MainActor
    private func applyParkWindow(_ pane: AgentPaneRef, workspace: String?, context: AgentApplyContext) {
        guard let node = pane.resolveNode(context: context), let sourceWindow = node.mostRecentWindowRecursive ?? node.anyLeafWindowRecursive else { return }
        let workspaceName = workspace ?? "__agent_parked"
        let targetWorkspace = getAgentTargetWorkspace(named: workspaceName, projectSource: node.nodeWorkspace, monitorSource: node)
        if node is Window, sourceWindow.isFloating {
            node.bind(to: targetWorkspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        } else {
            let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
            node.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
        }
    }

    @MainActor
    private func getAgentTargetWorkspace(named name: String, projectSource: Workspace?, monitorSource: TreeNode) -> Workspace {
        let existedBefore = Workspace.existing(byName: name) != nil
        let targetWorkspace = Workspace.get(byName: name)
        if !existedBefore {
            targetWorkspace.assignProject(projectSource?.projectId ?? focus.workspace.projectId)
        }
        targetWorkspace.seedMonitorIfNeeded(monitorSource.nodeMonitor ?? focus.workspace.workspaceMonitor)
        return targetWorkspace
    }
}
