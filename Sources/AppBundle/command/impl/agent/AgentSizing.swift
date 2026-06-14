import AppKit

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
    let ratios = agentResolvedSizeRatios(ratiosByChild: ratiosByChild, explicitTotal: explicitTotal, unspecifiedCount: unspecifiedCount)
    guard !ratios.isEmpty else { return }

    let totalWeight = container.getWeight(container.orientation)
    for (child, ratio) in zip(container.children, ratios) {
        child.setWeight(container.orientation, totalWeight * ratio)
    }
}

private func agentResolvedSizeRatios(
    ratiosByChild: [CGFloat?],
    explicitTotal: CGFloat,
    unspecifiedCount: Int,
) -> [CGFloat] {
    if explicitTotal > 1 || unspecifiedCount == 0 {
        let rawRatios = ratiosByChild.map { $0 ?? 1 }
        let total = rawRatios.reduce(CGFloat.zero, +)
        guard total > 0 else { return [] }
        return rawRatios.map { $0 / total }
    }
    let unspecifiedRatio = unspecifiedCount > 0 ? (1 - explicitTotal) / CGFloat(unspecifiedCount) : 0
    return ratiosByChild.map { $0 ?? unspecifiedRatio }
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
