struct AgentWindowTarget: Decodable {
    let windowId: UInt32?
    let match: AgentWindowMatch?

    @MainActor
    func resolveWindow() async throws -> Window? {
        if let windowId { return Window.get(byId: windowId) }
        guard let match else { return nil }
        for window in Workspace.all.flatMap(\.allLeafWindowsRecursive) {
            if try await match.matches(window) {
                return window
            }
        }
        return nil
    }
}

struct AgentWindowMatch: Decodable {
    let appName: String?
    let appBundleId: String?
    let titleContains: String?

    @MainActor
    func matches(_ window: Window) async throws -> Bool {
        if let appName, window.app.name != appName { return false }
        if let appBundleId, window.app.rawAppBundleId != appBundleId { return false }
        if let titleContains, try await !window.title.localizedCaseInsensitiveContains(titleContains) { return false }
        return true
    }
}
