extension AgentLayoutNode {
    @MainActor
    func applySizeRatios(to node: TreeNode) {
        guard case .split(_, let childSpecs, _) = self,
              let container = node as? TilingContainer,
              container.layout == .tiles
        else { return }

        applyAgentSizeRatios(to: container, childSpecs: childSpecs)
        for (child, childSpec) in zip(container.children, childSpecs) {
            childSpec.applySizeRatios(to: child)
        }
    }
}
