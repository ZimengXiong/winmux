struct AgentPaneRef: Codable {
    let paneId: String?
    let windowId: UInt32?
    let tabGroupId: String?

    @MainActor
    func resolveNode(context: AgentApplyContext? = nil) -> TreeNode? {
        if let paneId {
            if paneId.hasPrefix("pane-tabgroup-") {
                return resolveAgentTabGroup(String(paneId.dropFirst("pane-".count)), context: context)
            }
            if paneId.hasPrefix("pane-"), let windowId = UInt32(paneId.dropFirst("pane-".count)) {
                return Window.get(byId: windowId)
            }
        }
        if let windowId { return Window.get(byId: windowId) }
        if let tabGroupId { return resolveAgentTabGroup(tabGroupId, context: context) }
        return nil
    }

    @MainActor
    func canResolve(in context: AgentValidationContext) -> Bool {
        if resolveNode() != nil { return true }
        if let tabGroupId, context.plannedTabGroups[tabGroupId] != nil { return true }
        if let paneId, paneId.hasPrefix("pane-tabgroup-") {
            return context.plannedTabGroups[String(paneId.dropFirst("pane-".count))] != nil
        }
        return false
    }
}
