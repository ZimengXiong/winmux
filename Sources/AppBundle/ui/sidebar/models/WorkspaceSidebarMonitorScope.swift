import CoreGraphics

let workspaceSidebarFocusedScopeId = "focused"
let workspaceSidebarAllScopeId = "all"
private let workspaceSidebarMonitorScopePrefix = "monitor:"

func workspaceSidebarMonitorScopeId(for monitor: Monitor) -> String {
    workspaceSidebarMonitorScopeId(for: monitor.rect.topLeftCorner)
}

func workspaceSidebarMonitorScopeId(for point: CGPoint) -> String {
    "\(workspaceSidebarMonitorScopePrefix)\(point.x),\(point.y)"
}

func workspaceSidebarMonitorScopePoint(_ scopeId: String) -> CGPoint? {
    guard scopeId.hasPrefix(workspaceSidebarMonitorScopePrefix) else { return nil }
    let rawPoint = scopeId.dropFirst(workspaceSidebarMonitorScopePrefix.count)
    let parts = rawPoint.split(separator: ",", maxSplits: 1).compactMap { Double($0) }
    guard parts.count == 2 else { return nil }
    return CGPoint(x: parts[0], y: parts[1])
}

@MainActor
func workspaceSidebarMonitor(forScopeId scopeId: String) -> Monitor? {
    if scopeId == workspaceSidebarFocusedScopeId {
        return focus.workspace.workspaceMonitor
    }
    guard let point = workspaceSidebarMonitorScopePoint(scopeId) else { return nil }
    return sortedMonitors.first { $0.rect.topLeftCorner == point }
}

func workspaceSidebarWorkspaceMatchesScope(
    workspaceMonitorScopeId: String,
    selectedScopeId: String,
    focusedMonitorScopeId: String,
) -> Bool {
    switch selectedScopeId {
        case workspaceSidebarAllScopeId:
            true
        case workspaceSidebarFocusedScopeId:
            workspaceMonitorScopeId == focusedMonitorScopeId
        default:
            workspaceMonitorScopeId == selectedScopeId
    }
}
