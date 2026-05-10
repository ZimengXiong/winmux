import AppKit
import Common
import Foundation

// MARK: - Helpers

@MainActor
func currentAgentWorldId() -> String {
    let workspaces = userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).sortedBy(\.name)
    var lines: [String] = []
    for workspace in workspaces {
        lines.append("workspace|\(workspace.name)|visible:\(workspace.isVisible)|monitor:\(workspace.workspaceMonitor.monitorId_oneBased?.description ?? "nil")")
        lines.append(contentsOf: workspace.rootTilingContainer.agentWorldLines(prefix: "tree|\(workspace.name)"))
        for window in workspace.allLeafWindowsRecursive.sortedBy(\.windowId) {
            lines.append(
                [
                    "window",
                    window.windowId.description,
                    window.nodeWorkspace?.name ?? "nil",
                    window.agentPaneId ?? "nil",
                    window.nearestWindowTabGroup.map(agentTabGroupId) ?? "nil",
                    window.agentLayoutDescription,
                    "fullscreen:\(window.isFullscreen)",
                    "noOuterGaps:\(window.noOuterGapsInFullscreen)",
                ].joined(separator: "|")
            )
        }
        for group in workspace.rootTilingContainer.allAgentTabGroupsRecursive.sortedBy({ agentTabGroupId($0) }) {
            lines.append(
                [
                    "tabGroup",
                    agentTabGroupId(group),
                    group.nodeWorkspace?.name ?? "nil",
                    "active:\(group.tabActiveWindow?.windowId.description ?? "nil")",
                    "tabs:\(group.agentTabWindows.map(\.windowId).map(String.init).joined(separator: ","))",
                ].joined(separator: "|")
            )
        }
    }
    return stableAgentHash(lines.joined(separator: "\n"))
}

func stableAgentHash(_ input: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in input.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
}

func duplicateAgentWindowIds(in ids: [UInt32]) -> [UInt32] {
    var seen: Set<UInt32> = []
    var duplicates: Set<UInt32> = []
    for id in ids where !seen.insert(id).inserted {
        duplicates.insert(id)
    }
    return duplicates.sorted()
}

@MainActor
func resolveAgentTabGroup(_ id: String, context: AgentApplyContext? = nil) -> TilingContainer? {
    if let alias = context?.tabGroupAliases[id] {
        return alias
    }
    return Workspace.all
        .lazy
        .flatMap { $0.rootTilingContainer.allAgentTabGroupsRecursive }
        .first { agentTabGroupId($0) == id }
}

@MainActor
func agentTabGroupId(_ group: TilingContainer) -> String {
    let firstWindowId = group.agentTabWindows.first?.windowId ?? group.anyLeafWindowRecursive?.windowId ?? 0
    return "tabgroup-\(firstWindowId)"
}

func agentPaneIdForTabGroup(tabGroupId: String) -> String {
    "pane-\(tabGroupId)"
}

@MainActor
func reorderAgentTabGroup(_ group: TilingContainer, tabs: [UInt32]) {
    for tab in tabs {
        Window.get(byId: tab)?.bind(to: group, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
}

@MainActor
func agentMoveWindowToWorkspace(_ window: Window, _ targetWorkspace: Workspace, focusFollowsWindow: Bool) -> Bool {
    moveWindowToWorkspace(window, targetWorkspace, CmdIo(stdin: .emptyStdin), focusFollowsWindow: focusFollowsWindow, failIfNoop: false)
}

@MainActor
func setAgentPaneSize(_ node: TreeNode, axis: AgentLayoutDirection?, size: CGFloat) {
    guard let target = agentResizableNode(for: node, axis: axis) else { return }
    applyAgentSizeRatios(
        to: target.parent,
        ratiosByChild: target.parent.children.map { $0 === target.node ? size : nil },
    )
}

@MainActor
func applyAgentSizeRatios(to container: TilingContainer, childSpecs: [AgentLayoutNode]) {
    applyAgentSizeRatios(
        to: container,
        ratiosByChild: container.children.indices.map { index in
            index < childSpecs.count ? childSpecs[index].sizeRatio : nil
        },
    )
}

@MainActor
func applyAgentSizeRatios(to container: TilingContainer, ratiosByChild: [CGFloat?]) {
    guard container.layout == .tiles, !container.children.isEmpty else { return }
    let childCount = container.children.count
    let ratiosByChild = Array(ratiosByChild.prefix(childCount)) + Array(repeating: nil, count: max(0, childCount - ratiosByChild.count))
    let explicitTotal = ratiosByChild.compactMap { $0 }.reduce(CGFloat.zero, +)
    let unspecifiedCount = ratiosByChild.count - ratiosByChild.compactMap { $0 }.count
    let ratios: [CGFloat]

    if explicitTotal > 1 || unspecifiedCount == 0 {
        let rawRatios = ratiosByChild.map { $0 ?? 1 }
        let total = rawRatios.reduce(CGFloat.zero, +)
        guard total > 0 else { return }
        ratios = rawRatios.map { $0 / total }
    } else {
        let unspecifiedRatio = unspecifiedCount > 0 ? (1 - explicitTotal) / CGFloat(unspecifiedCount) : 0
        ratios = ratiosByChild.map { $0 ?? unspecifiedRatio }
    }

    let totalWeight = container.getWeight(container.orientation)
    for (child, ratio) in zip(container.children, ratios) {
        child.setWeight(container.orientation, totalWeight * ratio)
    }
}

@MainActor
func agentResizableNode(for node: TreeNode, axis: AgentLayoutDirection? = nil) -> (node: TreeNode, parent: TilingContainer)? {
    let paneNode = node.agentPaneSizingNode
    for candidate in paneNode.parentsWithSelf {
        guard let parent = candidate.parent as? TilingContainer,
              parent.layout == .tiles,
              axis == nil || parent.orientation == axis?.orientation
        else { continue }
        return (candidate, parent)
    }
    return nil
}

@MainActor
func placeAgentPane(_ source: TreeNode, relation: AgentPaneRelationKind, target: TreeNode) {
    if source == target || source.parentsWithSelf.contains(target) || target.parentsWithSelf.contains(source) {
        return
    }
    if let insertion = target.agentNearestInsertionParent(orientation: relation.orientation) {
        var insertIndex = insertion.anchor.ownIndex.orDie() + (relation.sourceIsAfterTarget ? 1 : 0)
        if source.parent === insertion.parent, let sourceIndex = source.ownIndex, sourceIndex < insertIndex {
            insertIndex -= 1
        }
        source.bind(to: insertion.parent, adaptiveWeight: WEIGHT_AUTO, index: insertIndex)
        source.mostRecentWindowRecursive?.markAsMostRecentChild()
        return
    }

    _ = source.unbindFromParent()
    guard target.parent != nil else { return }
    let targetBinding = target.unbindFromParent()
    let newParent = TilingContainer(parent: targetBinding.parent, adaptiveWeight: targetBinding.adaptiveWeight, relation.orientation, .tiles, index: targetBinding.index)
    if relation.sourceIsAfterTarget {
        target.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        source.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    } else {
        source.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        target.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
    source.mostRecentWindowRecursive?.markAsMostRecentChild()
}

extension TreeNode {
    @MainActor
    var agentPaneId: String? {
        if let group = (self as? Window)?.nearestWindowTabGroup {
            return agentPaneIdForTabGroup(tabGroupId: agentTabGroupId(group))
        }
        if let window = self as? Window {
            return "pane-\(window.windowId)"
        }
        if let group = self as? TilingContainer, group.isWindowTabGroup {
            return agentPaneIdForTabGroup(tabGroupId: agentTabGroupId(group))
        }
        return nil
    }

    func agentNearestInsertionParent(orientation: Orientation) -> (parent: TilingContainer, anchor: TreeNode)? {
        for node in parentsWithSelf {
            guard let parent = node.parent as? TilingContainer,
                  parent.layout == .tiles,
                  parent.orientation == orientation,
                  let anchor = node.directChild(in: parent)
            else { continue }
            return (parent, anchor)
        }
        return nil
    }

    @MainActor
    var agentPaneSizingNode: TreeNode {
        (self as? Window)?.nearestWindowTabGroup ?? self
    }

    @MainActor
    var agentSizeRatio: CGFloat? {
        guard let parent = parent as? TilingContainer,
              parent.layout == .tiles
        else { return nil }
        let total = parent.children.reduce(CGFloat.zero) { $0 + $1.getWeight(parent.orientation) }
        guard total > 0 else { return nil }
        return getWeight(parent.orientation) / total
    }

    @MainActor
    var agentSizeAxis: AgentLayoutDirection? {
        guard let parent = parent as? TilingContainer,
              parent.layout == .tiles
        else { return nil }
        return parent.orientation == .h ? .horizontal : .vertical
    }
}

extension Window {
    @MainActor
    var agentLayoutDescription: String {
        guard let parent else { return "unbound" }
        return switch getChildParentRelation(child: self, parent: parent) {
            case .floatingWindow: "floating"
            case .tiling(let parent): "\(parent.orientation.rawValue)_\(parent.layout.rawValue)"
            case .macosNativeFullscreenWindow: "macos_native_fullscreen"
            case .macosNativeHiddenAppWindow: "macos_native_hidden_app"
            case .macosNativeMinimizedWindow: "macos_native_minimized"
            case .macosPopupWindow: "macos_popup"
            case .rootTilingContainer, .shimContainerRelation: "internal"
        }
    }
}

extension TilingContainer {
    @MainActor
    var allAgentTabGroupsRecursive: [TilingContainer] {
        var result: [TilingContainer] = []
        func visit(_ node: TreeNode) {
            guard let container = node as? TilingContainer else { return }
            if container.isWindowTabGroup {
                result.append(container)
                return
            }
            for child in container.children {
                visit(child)
            }
        }
        visit(self)
        return result
    }

    @MainActor
    var agentTabWindows: [Window] {
        children.compactMap { $0.tabRepresentativeWindow ?? $0.mostRecentWindowRecursive ?? $0.anyLeafWindowRecursive }
    }

    @MainActor
    func agentRawLayoutNode() -> AgentRawLayoutNode {
        if isWindowTabGroup {
            return .tabGroup(
                tabGroupId: agentTabGroupId(self),
                activeWindowId: tabActiveWindow?.windowId,
                tabs: agentTabWindows.map(\.windowId),
                size: agentSizeRatio,
            )
        }
        return .split(
            direction: orientation == .h ? .horizontal : .vertical,
            layout: layout.rawValue,
            size: agentSizeRatio,
            children: children.compactMap { child in
                if let window = child as? Window {
                    return .window(windowId: window.windowId, size: window.agentSizeRatio)
                }
                if let container = child as? TilingContainer {
                    return container.agentRawLayoutNode()
                }
                return nil
            },
        )
    }

    @MainActor
    func agentWorldLines(prefix: String) -> [String] {
        let nodeId: String
        if isWindowTabGroup {
            nodeId = "tabGroup:\(agentTabGroupId(self))"
        } else {
            nodeId = "container:\(orientation.rawValue):\(layout.rawValue)"
        }
        let weight = (parent as? TilingContainer).map { "|weight:\(getWeight($0.orientation))" } ?? ""
        var result = ["\(prefix)|\(nodeId)\(weight)|children:\(children.count)"]
        for (index, child) in children.enumerated() {
            let childPrefix = "\(prefix).\(index)"
            if let window = child as? Window {
                result.append("\(childPrefix)|window:\(window.windowId)|weight:\(window.getWeight(orientation))")
            } else if let container = child as? TilingContainer {
                result.append(contentsOf: container.agentWorldLines(prefix: childPrefix))
            }
        }
        return result
    }
}

extension Workspace {
    @MainActor
    func agentPaneInfos() -> [AgentPaneInfo] {
        var result: [AgentPaneInfo] = floatingWindows.map {
            AgentPaneInfo(
                paneId: "pane-\($0.windowId)",
                kind: .window,
                workspace: name,
                windowId: $0.windowId,
                tabGroupId: nil,
                label: $0.app.name ?? $0.app.rawAppBundleId ?? "Window \($0.windowId)",
                size: $0.agentPaneSizingNode.agentSizeRatio,
                sizeAxis: $0.agentPaneSizingNode.agentSizeAxis,
                frame: ($0.lastKnownActualRect ?? $0.lastAppliedLayoutPhysicalRect ?? $0.lastAppliedLayoutVirtualRect).map(AgentRect.init),
            )
        }

        func visit(_ node: TreeNode) {
            switch node.nodeCases {
                case .window(let window):
                    result.append(AgentPaneInfo(
                        paneId: "pane-\(window.windowId)",
                        kind: .window,
                        workspace: name,
                        windowId: window.windowId,
                        tabGroupId: nil,
                        label: window.app.name ?? window.app.rawAppBundleId ?? "Window \(window.windowId)",
                        size: window.agentPaneSizingNode.agentSizeRatio,
                        sizeAxis: window.agentPaneSizingNode.agentSizeAxis,
                        frame: (window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect ?? window.lastAppliedLayoutVirtualRect).map(AgentRect.init),
                    ))
                case .tilingContainer(let container):
                    if container.isWindowTabGroup {
                        let tabGroupId = agentTabGroupId(container)
                        result.append(AgentPaneInfo(
                            paneId: agentPaneIdForTabGroup(tabGroupId: tabGroupId),
                            kind: .tabGroup,
                            workspace: name,
                            windowId: nil,
                            tabGroupId: tabGroupId,
                            label: "Tab Group \(container.agentTabWindows.map(\.windowId))",
                            size: container.agentSizeRatio,
                            sizeAxis: container.agentSizeAxis,
                            frame: (container.lastAppliedLayoutPhysicalRect ?? container.lastAppliedLayoutVirtualRect).map(AgentRect.init),
                        ))
                    } else {
                        for child in container.children { visit(child) }
                    }
                case .workspace, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                     .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer:
                    break
            }
        }
        visit(rootTilingContainer)
        return result
    }

    @MainActor
    func agentPaneRelations() -> [AgentPaneRelation] {
        var byPane: [String: AgentPaneRelation] = [:]
        func relation(_ paneId: String) -> AgentPaneRelation {
            byPane[paneId] ?? AgentPaneRelation(workspace: name, paneId: paneId)
        }
        func set(_ paneId: String, _ keyPath: WritableKeyPath<AgentPaneRelation, String?>, _ value: String?) {
            guard let value else { return }
            var item = relation(paneId)
            item[keyPath: keyPath] = value
            byPane[paneId] = item
        }
        func paneIds(_ node: TreeNode) -> [String] {
            if let paneId = node.agentPaneId { return [paneId] }
            return node.children.flatMap(paneIds)
        }
        func visit(_ node: TreeNode) {
            guard let container = node as? TilingContainer, !container.isWindowTabGroup else { return }
            let childPaneIds = container.children.map(paneIds)
            for index in childPaneIds.indices.dropLast() {
                for lhs in childPaneIds[index] {
                    for rhs in childPaneIds[index + 1] {
                        if container.orientation == .h {
                            set(lhs, \.right, rhs)
                            set(rhs, \.left, lhs)
                        } else {
                            set(lhs, \.below, rhs)
                            set(rhs, \.above, lhs)
                        }
                    }
                }
            }
            for child in container.children { visit(child) }
        }
        visit(rootTilingContainer)
        return Array(byPane.values)
    }
}
