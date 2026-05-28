import AppKit

@MainActor
func workspaceSidebarResolvedPanelMonitor() -> Monitor {
    if isMouseWindowDragInProgress() {
        return mouseLocation.monitorApproximation
    }
    return config.workspaceSidebar.resolvedMonitor(sortedMonitors: sortedMonitors) ?? mainMonitor
}

@MainActor
func workspaceSidebarResolvedPanelMonitors() -> [Monitor] {
    let resolved = config.workspaceSidebar.resolvedMonitors(sortedMonitors: sortedMonitors)
    return resolved.isEmpty ? [mainMonitor] : resolved
}

@MainActor
func buildWorkspaceSidebarMonitorScopes(
    sortedMonitors: [Monitor],
    focusedMonitorScopeId: String,
) -> [WorkspaceSidebarMonitorScopeViewModel] {
    var scopes = [
        WorkspaceSidebarMonitorScopeViewModel(
            id: workspaceSidebarDefaultScopeId,
            displayName: "Default",
            subtitle: nil,
            systemImageName: "display",
            isFocusedMonitor: false,
        ),
    ]
    if config.workspaceSidebar.enableFocus {
        scopes.append(WorkspaceSidebarMonitorScopeViewModel(
            id: workspaceSidebarFocusedScopeId,
            displayName: "Focused",
            subtitle: nil,
            systemImageName: "scope",
            isFocusedMonitor: false,
        ))
    }
    return scopes + sortedMonitors.enumerated().map { index, monitor in
        let scopeId = workspaceSidebarMonitorScopeId(for: monitor)
        return WorkspaceSidebarMonitorScopeViewModel(
            id: scopeId,
            displayName: workspaceSidebarMonitorDisplayName(monitor, fallbackIndex: index + 1),
            subtitle: monitor.isMain ? monitor.name : nil,
            systemImageName: "display",
            isFocusedMonitor: scopeId == focusedMonitorScopeId,
        )
    }
}

func workspaceSidebarMonitorDisplayName(_ monitor: Monitor, fallbackIndex: Int) -> String {
    let name = monitor.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if monitor.isMain {
        return "Main"
    }
    return name.isEmpty ? "Display \(fallbackIndex)" : name
}
