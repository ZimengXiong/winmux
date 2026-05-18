import AppKit

extension CGPoint {
    @MainActor
    func findWindowDragTarget(in tree: TilingContainer, excluding excludedNode: TreeNode? = nil) -> Window? {
        findWindowDragTarget(in: tree as TreeNode, excluding: excludedNode)
    }

    @MainActor
    func shouldExcludeDragTargetNode(_ node: TreeNode, excludedNode: TreeNode?) -> Bool {
        guard let excludedNode else { return false }
        guard let excludedTabGroup = excludedNode as? TilingContainer,
              excludedTabGroup.layout == .tabGroup
        else {
            if node === excludedNode { return true }
            return node.parentsWithSelf.contains(excludedNode)
        }
        if node === excludedTabGroup { return false }
        if let window = node as? Window, window.parent === excludedTabGroup {
            return false
        }
        return node.parentsWithSelf.contains(excludedNode)
    }

    @MainActor
    func findWindowDragTarget(in node: TreeNode, excluding excludedNode: TreeNode?) -> Window? {
        if shouldExcludeDragTargetNode(node, excludedNode: excludedNode) {
            return nil
        }
        guard node.windowDragVisibleRect?.contains(self) == true else { return nil }
        switch node.tilingTreeNodeCasesOrDie() {
            case .window(let window):
                return window
            case .tilingContainer(let container):
                return findWindowDragTargetInContainer(container, excluding: excludedNode)
        }
    }

    @MainActor
    private func findWindowDragTargetInContainer(_ container: TilingContainer, excluding excludedNode: TreeNode?) -> Window? {
        switch container.layout {
            case .tiles:
                return findWindowDragTargetInTiles(container, excluding: excludedNode)
            case .tabGroup:
                return findWindowDragTargetInTabGroup(container, excluding: excludedNode)
        }
    }

    @MainActor
    private func findWindowDragTargetInTiles(_ container: TilingContainer, excluding excludedNode: TreeNode?) -> Window? {
        let candidates = container.childrenByMostRecentUse.filter { $0.windowDragVisibleRect?.contains(self) == true }
        logOverlappingDragTargetsIfNeeded(candidates: candidates, container: container, excludedNode: excludedNode)
        for child in candidates {
            if let window = findWindowDragTarget(in: child, excluding: excludedNode) {
                return window
            }
        }
        return nil
    }

    @MainActor
    private func findWindowDragTargetInTabGroup(_ container: TilingContainer, excluding excludedNode: TreeNode?) -> Window? {
        if container.usesWindowTabBehavior {
            guard let targetWindow = container.tabActiveWindow ??
                container.mostRecentWindowRecursive ??
                container.anyLeafWindowRecursive
            else { return nil }
            return shouldExcludeDragTargetNode(targetWindow, excludedNode: excludedNode) ? nil : targetWindow
        }
        let candidates = container.childrenByMostRecentUse.filter { $0.windowDragVisibleRect?.contains(self) == true }
        for child in candidates {
            if let window = findWindowDragTarget(in: child, excluding: excludedNode) {
                return window
            }
        }
        return nil
    }

    @MainActor
    private func logOverlappingDragTargetsIfNeeded(candidates: [TreeNode], container: TilingContainer, excludedNode: TreeNode?) {
        guard candidates.count > 1 else { return }
        let candidateSummary = candidates.map { candidate in
            if let window = candidate as? Window {
                return "w:\(window.windowId) visible=\(debugDescribe(candidate.windowDragVisibleRect))"
            }
            return "node:\(ObjectIdentifier(candidate)) visible=\(debugDescribe(candidate.windowDragVisibleRect))"
        }.joined(separator: " | ")
        let signature = "surface-overlap:container=\(ObjectIdentifier(container).hashValue):excluded=\(ObjectIdentifier(excludedNode ?? NilTreeNode.instance).hashValue):candidates=\(candidates.map { ObjectIdentifier($0).hashValue })"
        logWindowDragHitTestIfNeeded(
            signature: signature,
            "windowDragTarget.overlap mouse=\(debugDescribe(self)) container=\(ObjectIdentifier(container)) excluded=\(String(describing: excludedNode.map(ObjectIdentifier.init))) candidates=[\(candidateSummary)]"
        )
    }
}
