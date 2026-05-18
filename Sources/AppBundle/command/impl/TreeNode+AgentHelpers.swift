import AppKit
import Common

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
