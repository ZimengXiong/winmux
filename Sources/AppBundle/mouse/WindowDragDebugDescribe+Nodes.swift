@MainActor
func debugDescribe(_ window: Window?) -> String {
    guard let window else { return "nil" }
    return "w:\(window.windowId) actual=\(debugDescribe(window.lastKnownActualRect)) layout=\(debugDescribe(window.lastAppliedLayoutPhysicalRect)) visible=\(debugDescribe(window.windowDragVisibleRect)) moveVisible=\(debugDescribe(window.moveNode.windowDragVisibleRect))"
}

@MainActor
func debugDescribe(_ node: TreeNode) -> String {
    switch node.tilingTreeNodeCasesOrDie() {
        case .window(let window):
            return "window[\(window.windowId)] visible=\(debugDescribe(node.windowDragVisibleRect))"
        case .tilingContainer(let container):
            return "container[\(ObjectIdentifier(container).hashValue)] layout=\(container.layout) visible=\(debugDescribe(node.windowDragVisibleRect))"
    }
}
