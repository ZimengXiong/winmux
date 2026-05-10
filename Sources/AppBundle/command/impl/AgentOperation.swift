import AppKit
import Common
import Foundation

// MARK: - Operations

enum AgentOperation: Decodable {
    case focusWindow(AgentWindowTarget)
    case focusWorkspace(workspace: String)
    case moveWindowToWorkspace(windowId: UInt32, workspace: String, focus: Bool?)
    case moveTabGroupToWorkspace(tabGroupId: String, workspace: String, focus: Bool?)
    case swapPanes(a: AgentPaneRef, b: AgentPaneRef)
    case placePane(pane: AgentPaneRef, relation: AgentPaneRelationKind, target: AgentPaneRef)
    case createTabGroup(tabGroupId: String?, workspace: String?, tabs: [UInt32], activeWindowId: UInt32?)
    case addWindowToTabGroup(windowId: UInt32, tabGroupId: String, activeWindowId: UInt32?)
    case moveWindowOutOfTabGroup(windowId: UInt32)
    case setActiveTab(tabGroupId: String, windowId: UInt32)
    case setWinMuxFullscreen(windowId: UInt32, value: Bool, noOuterGaps: Bool?)
    case setFloating(windowId: UInt32, value: Bool)
    case closeWindow(windowId: UInt32, quitAppIfLastWindow: Bool?)
    case parkWindow(AgentPaneRef, workspace: String?)
    case setPaneSize(pane: AgentPaneRef, axis: AgentLayoutDirection?, size: CGFloat)
    case setWorkspaceLayout(AgentWorkspaceLayout)

    enum CodingKeys: String, CodingKey {
        case type
        case workspace
        case windowId
        case windowId1
        case windowId2
        case tabGroupId
        case focus
        case a
        case b
        case pane
        case paneId1
        case paneId2
        case relation
        case target
        case tabs
        case windows
        case activeWindowId
        case value
        case noOuterGaps
        case quitAppIfLastWindow
        case axis
        case direction
        case size
        case sizePercent
        case layout
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        switch normalizedAgentOperationType(rawType) {
            case "focuswindow":
                self = .focusWindow(try AgentWindowTarget(from: decoder))
            case "focusworkspace":
                self = .focusWorkspace(workspace: try container.decode(String.self, forKey: .workspace))
            case "movewindowtoworkspace":
                self = .moveWindowToWorkspace(
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                    workspace: try container.decode(String.self, forKey: .workspace),
                    focus: try container.decodeIfPresent(Bool.self, forKey: .focus),
                )
            case "movetabgrouptoworkspace":
                self = .moveTabGroupToWorkspace(
                    tabGroupId: try container.decode(String.self, forKey: .tabGroupId),
                    workspace: try container.decode(String.self, forKey: .workspace),
                    focus: try container.decodeIfPresent(Bool.self, forKey: .focus),
                )
            case "swappanes", "swap", "swapwindows":
                self = .swapPanes(
                    a: try container.decodeAgentPaneRef(primaryKey: .a, paneIdKey: .paneId1, windowIdKey: .windowId1),
                    b: try container.decodeAgentPaneRef(primaryKey: .b, paneIdKey: .paneId2, windowIdKey: .windowId2),
                )
            case "placepane":
                self = .placePane(
                    pane: try container.decode(AgentPaneRef.self, forKey: .pane),
                    relation: try container.decode(AgentPaneRelationKind.self, forKey: .relation),
                    target: try container.decode(AgentPaneRef.self, forKey: .target),
                )
            case "createtabgroup":
                self = .createTabGroup(
                    tabGroupId: try container.decodeIfPresent(String.self, forKey: .tabGroupId),
                    workspace: try container.decodeIfPresent(String.self, forKey: .workspace),
                    tabs: try container.decodeWindowIdArray(primaryKey: .tabs, aliasKey: .windows),
                    activeWindowId: try container.decodeIfPresent(UInt32.self, forKey: .activeWindowId),
                )
            case "addwindowtotabgroup":
                self = .addWindowToTabGroup(
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                    tabGroupId: try container.decode(String.self, forKey: .tabGroupId),
                    activeWindowId: try container.decodeIfPresent(UInt32.self, forKey: .activeWindowId),
                )
            case "movewindowoutoftabgroup":
                self = .moveWindowOutOfTabGroup(windowId: try container.decode(UInt32.self, forKey: .windowId))
            case "setactivetab":
                self = .setActiveTab(
                    tabGroupId: try container.decode(String.self, forKey: .tabGroupId),
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                )
            case "setwinmuxfullscreen", "setfullscreen":
                self = .setWinMuxFullscreen(
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                    value: try container.decode(Bool.self, forKey: .value),
                    noOuterGaps: try container.decodeIfPresent(Bool.self, forKey: .noOuterGaps),
                )
            case "setfloating":
                self = .setFloating(
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                    value: try container.decode(Bool.self, forKey: .value),
                )
            case "closewindow":
                self = .closeWindow(
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                    quitAppIfLastWindow: try container.decodeIfPresent(Bool.self, forKey: .quitAppIfLastWindow),
                )
            case "parkwindow":
                self = .parkWindow(
                    try container.decode(AgentPaneRef.self, forKey: .pane),
                    workspace: try container.decodeIfPresent(String.self, forKey: .workspace),
                )
            case "setpanesize", "resizepane":
                self = .setPaneSize(
                    pane: try container.decode(AgentPaneRef.self, forKey: .pane),
                    axis: try container.decodeAgentSizeAxis(axisKey: .axis, directionKey: .direction),
                    size: try container.decodeAgentSizeRatio(sizeKey: .size, percentKey: .sizePercent),
                )
            case "setworkspacelayout":
                self = .setWorkspaceLayout(try container.decode(AgentWorkspaceLayout.self, forKey: .layout))
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown agent operation type '\(rawType)'")
        }
    }

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
            case .addWindowToTabGroup(let windowId, _, let activeWindowId):
                if Window.get(byId: windowId) == nil { errors.append("addWindowToTabGroup: window \(windowId) does not exist") }
                if let activeWindowId, Window.get(byId: activeWindowId) == nil { errors.append("addWindowToTabGroup: active window \(activeWindowId) does not exist") }
                if case .addWindowToTabGroup(_, let tabGroupId, _) = self, resolveAgentTabGroup(tabGroupId) == nil {
                    if context.plannedTabGroups[tabGroupId] == nil {
                        errors.append("addWindowToTabGroup: tab group '\(tabGroupId)' does not exist")
                    }
                }
            case .setActiveTab(let tabGroupId, let windowId):
                let isExistingTab = resolveAgentTabGroup(tabGroupId)?.agentTabWindows.contains(where: { $0.windowId == windowId }) == true
                let isPlannedTab = context.plannedTabGroups[tabGroupId]?.contains(windowId) == true
                if !isExistingTab && !isPlannedTab {
                    errors.append("setActiveTab: window \(windowId) is not in tab group '\(tabGroupId)'")
                }
            case .parkWindow(let pane, _):
                if !pane.canResolve(in: context) { errors.append("parkWindow: pane does not exist") }
            case .setPaneSize(let pane, let axis, _):
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
            case .setWorkspaceLayout(let layout):
                try await layout.validate(appendTo: &errors)
        }
    }

    @MainActor
    func apply(context: inout AgentApplyContext) async throws {
        switch self {
            case .focusWindow(let target):
                _ = try await target.resolveWindow()?.focusWindow()
            case .focusWorkspace(let workspace):
                _ = Workspace.existing(byName: workspace)?.focusWorkspace()
            case .moveWindowToWorkspace(let windowId, let workspace, let shouldFocus):
                guard let window = Window.get(byId: windowId) else { return }
                let existedBefore = Workspace.existing(byName: workspace) != nil
                let targetWorkspace = Workspace.get(byName: workspace)
                if !existedBefore {
                    targetWorkspace.assignProject(window.nodeWorkspace?.projectId ?? focus.workspace.projectId)
                }
                targetWorkspace.seedMonitorIfNeeded(window.nodeMonitor ?? focus.workspace.workspaceMonitor)
                _ = agentMoveWindowToWorkspace(window, targetWorkspace, focusFollowsWindow: shouldFocus ?? false)
            case .moveTabGroupToWorkspace(let tabGroupId, let workspace, let shouldFocus):
                guard let group = resolveAgentTabGroup(tabGroupId, context: context) else { return }
                let existedBefore = Workspace.existing(byName: workspace) != nil
                let targetWorkspace = Workspace.get(byName: workspace)
                if !existedBefore {
                    targetWorkspace.assignProject(group.nodeWorkspace?.projectId ?? focus.workspace.projectId)
                }
                targetWorkspace.seedMonitorIfNeeded(group.nodeMonitor ?? focus.workspace.workspaceMonitor)
                let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
                group.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
                if shouldFocus ?? false { _ = group.mostRecentWindowRecursive?.focusWindow() }
            case .swapPanes(let a, let b):
                guard let nodeA = a.resolveNode(context: context), let nodeB = b.resolveNode(context: context) else { return }
                swapNodes(nodeA, nodeB)
            case .placePane(let pane, let relation, let target):
                guard let source = pane.resolveNode(context: context), let target = target.resolveNode(context: context) else { return }
                placeAgentPane(source, relation: relation, target: target)
            case .createTabGroup(let tabGroupId, let workspace, let tabs, let activeWindowId):
                let windows = tabs.compactMap { Window.get(byId: $0) }
                guard let first = windows.first else { return }
                let workspaceName = workspace ?? first.nodeWorkspace?.name ?? focus.workspace.name
                let existedBefore = Workspace.existing(byName: workspaceName) != nil
                let targetWorkspace = Workspace.get(byName: workspaceName)
                if !existedBefore {
                    targetWorkspace.assignProject(first.nodeWorkspace?.projectId ?? focus.workspace.projectId)
                }
                targetWorkspace.seedMonitorIfNeeded(first.nodeMonitor ?? focus.workspace.workspaceMonitor)
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
            case .addWindowToTabGroup(let windowId, let tabGroupId, let activeWindowId):
                guard let window = Window.get(byId: windowId), let group = resolveAgentTabGroup(tabGroupId, context: context), let target = group.agentTabWindows.first else { return }
                createOrAppendWindowTabStack(sourceWindow: window, onto: target)
                if let activeWindowId {
                    Window.get(byId: activeWindowId)?.markAsMostRecentChild()
                    _ = Window.get(byId: activeWindowId)?.focusWindow()
                }
            case .moveWindowOutOfTabGroup(let windowId):
                guard let window = Window.get(byId: windowId) else { return }
                _ = removeWindowFromTabStack(window)
            case .setActiveTab(let tabGroupId, let windowId):
                guard let window = Window.get(byId: windowId),
                      resolveAgentTabGroup(tabGroupId, context: context)?.agentTabWindows.contains(where: { $0 == window }) == true
                else { return }
                window.markAsMostRecentChild()
                _ = window.focusWindow()
            case .setWinMuxFullscreen(let windowId, let value, let noOuterGaps):
                guard let window = Window.get(byId: windowId) else { return }
                window.isFullscreen = value
                window.noOuterGapsInFullscreen = noOuterGaps ?? window.noOuterGapsInFullscreen
                window.markAsMostRecentChild()
            case .setFloating(let windowId, let value):
                guard let window = Window.get(byId: windowId), let workspace = window.nodeWorkspace else { return }
                if value {
                    window.bindAsFloatingWindow(to: workspace)
                } else if window.isFloating {
                    let binding = workspaceAppendBindingData(targetWorkspace: workspace, index: INDEX_BIND_LAST)
                    window.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
                }
            case .closeWindow(let windowId, let quitAppIfLastWindow):
                if quitAppIfLastWindow ?? false {
                    var args = CloseCmdArgs(rawArgs: [])
                    args.windowId = windowId
                    args.quitIfLastWindow = true
                    _ = try await CloseCommand(args: args).run(.defaultEnv, .emptyStdin)
                } else {
                    Window.get(byId: windowId)?.closeAxWindow()
                }
            case .parkWindow(let pane, let workspace):
                guard let node = pane.resolveNode(context: context), let sourceWindow = node.mostRecentWindowRecursive ?? node.anyLeafWindowRecursive else { return }
                let workspaceName = workspace ?? "__agent_parked"
                let existedBefore = Workspace.existing(byName: workspaceName) != nil
                let targetWorkspace = Workspace.get(byName: workspaceName)
                if !existedBefore {
                    targetWorkspace.assignProject(node.nodeWorkspace?.projectId ?? focus.workspace.projectId)
                }
                targetWorkspace.seedMonitorIfNeeded(node.nodeMonitor ?? focus.workspace.workspaceMonitor)
                if node is Window, sourceWindow.isFloating {
                    node.bind(to: targetWorkspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                } else {
                    let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
                    node.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
                }
            case .setPaneSize(let pane, let axis, let size):
                guard let node = pane.resolveNode(context: context) else { return }
                setAgentPaneSize(node, axis: axis, size: size)
            case .setWorkspaceLayout(let layout):
                try await layout.apply()
        }
    }
}

