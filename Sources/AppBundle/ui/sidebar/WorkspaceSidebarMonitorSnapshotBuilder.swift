import AppKit

@MainActor
func workspaceSidebarSelectedProjectMonitor(
    selectedScopeId: String,
    focusedMonitor: Monitor,
    sortedMonitors: [Monitor],
) -> Monitor {
    guard selectedScopeId != workspaceSidebarDefaultScopeId,
          selectedScopeId != workspaceSidebarFocusedScopeId,
          selectedScopeId != workspaceSidebarAllScopeId
    else {
        return focusedMonitor
    }
    return sortedMonitors.first { workspaceSidebarMonitorScopeId(for: $0) == selectedScopeId } ?? focusedMonitor
}

@MainActor
func workspaceSidebarResolvedPanelMonitor() -> Monitor {
    if isMouseWindowDragInProgress() {
        return mouseLocation.monitorApproximation
    }
    return config.workspaceSidebar.resolvedMonitor(sortedMonitors: sortedMonitors) ?? mainMonitor
}

@MainActor
func buildWorkspaceSidebarMonitorScopes(
    sortedMonitors: [Monitor],
    focusedMonitorScopeId: String,
) -> [WorkspaceSidebarMonitorScopeViewModel] {
    [
        WorkspaceSidebarMonitorScopeViewModel(
            id: workspaceSidebarDefaultScopeId,
            displayName: "Default",
            subtitle: nil,
            systemImageName: "display",
            isFocusedMonitor: false,
        ),
        WorkspaceSidebarMonitorScopeViewModel(
            id: workspaceSidebarFocusedScopeId,
            displayName: "Focused",
            subtitle: nil,
            systemImageName: "scope",
            isFocusedMonitor: false,
        ),
        WorkspaceSidebarMonitorScopeViewModel(
            id: workspaceSidebarAllScopeId,
            displayName: "All",
            subtitle: nil,
            systemImageName: "rectangle.grid.2x2",
            isFocusedMonitor: false,
        ),
    ] + sortedMonitors.enumerated().map { index, monitor in
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
