import AppKit

func sanitizedWorkspaceSidebarHoveredWorkspaceName(
    visibleWorkspaceNames: Set<String>,
    hoveredWorkspaceName: String?,
) -> String? {
    guard let hoveredWorkspaceName,
          visibleWorkspaceNames.contains(hoveredWorkspaceName)
    else {
        return nil
    }
    return hoveredWorkspaceName
}

func resolvedWorkspaceSidebarSelectedProjectId(
    validProjectIds: Set<String>,
    activeProjectId: String,
) -> String {
    if validProjectIds.contains(activeProjectId) {
        return activeProjectId
    }
    if validProjectIds.contains(workspaceProjectDefaultId) {
        return workspaceProjectDefaultId
    }
    return validProjectIds.sorted().first ?? workspaceProjectDefaultId
}

@MainActor
func updateWorkspaceSidebarModel() async {
    guard TrayMenuModel.shared.isEnabled, config.workspaceSidebar.enabled else {
        if !TrayMenuModel.shared.workspaceSidebarWorkspaces.isEmpty {
            TrayMenuModel.shared.workspaceSidebarWorkspaces = []
        }
        if !TrayMenuModel.shared.workspaceSidebarMonitorScopes.isEmpty {
            TrayMenuModel.shared.workspaceSidebarMonitorScopes = []
        }
        if !TrayMenuModel.shared.workspaceSidebarProjects.isEmpty {
            TrayMenuModel.shared.workspaceSidebarProjects = []
        }
        TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector = false
        WorkspaceSidebarPanel.shared.refresh()
        return
    }

    let currentFocus = focus
    let workspaceLabels = config.workspaceSidebar.workspaceLabels
    let previousTopPadding = TrayMenuModel.shared.workspaceSidebarTopPadding
    pruneCachedWindowTitles()

    let availableMonitors = sortedMonitors
    let focusedMonitorScopeId = workspaceSidebarMonitorScopeId(for: currentFocus.workspace.workspaceMonitor)
    let projectMonitor = workspaceSidebarSelectedProjectMonitor(
        selectedScopeId: TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId,
        focusedMonitor: currentFocus.workspace.workspaceMonitor,
        sortedMonitors: availableMonitors,
    )
    let monitorScopes = buildWorkspaceSidebarMonitorScopes(
        sortedMonitors: availableMonitors,
        focusedMonitorScopeId: focusedMonitorScopeId,
    )
    let validScopeIds = Set(monitorScopes.map(\.id))
    let defaultMonitorScopeId = availableMonitors.count > 1
        ? workspaceSidebarAllScopeId
        : workspaceSidebarFocusedScopeId
    let selectedMonitorScopeId = validScopeIds.contains(TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId)
        ? TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId
        : defaultMonitorScopeId
    let projects = buildWorkspaceSidebarProjectViewModels()
    let validProjectIds = Set(projects.map(\.id))
    let selectedProjectId = resolvedWorkspaceSidebarSelectedProjectId(
        validProjectIds: validProjectIds,
        activeProjectId: activeWorkspaceProjectId(for: projectMonitor),
    )

    let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspaceSidebarResolvedPanelMonitor())
    TrayMenuModel.shared.workspaceSidebarTopPadding = CGFloat(gaps.outer.top)
    let didTopPaddingChange = TrayMenuModel.shared.workspaceSidebarTopPadding != previousTopPadding

    var sidebarWorkspaces: [WorkspaceSidebarWorkspaceViewModel] = []
    for workspace in Workspace.all {
        if !shouldShowWorkspaceInSidebar(workspace, currentFocus: currentFocus, isEditingWorkspace: false) {
            continue
        }
        let sidebarItems = await buildWorkspaceSidebarItems(for: workspace, currentFocus: currentFocus)

        let sidebarLabel = workspaceLabels[workspace.name] ?? ""
        let isGeneratedName = isSidebarDraftWorkspaceName(workspace.name) || workspace.usesAutomaticDisplayName
        let displayName = workspaceDisplayName(workspace.name)
        let workspaceMonitor = workspace.workspaceMonitor

        sidebarWorkspaces.append(
            WorkspaceSidebarWorkspaceViewModel(
                name: workspace.name,
                projectId: workspace.projectId,
                displayName: displayName,
                sidebarLabel: sidebarLabel,
                isGeneratedName: isGeneratedName,
                monitorScopeId: workspaceSidebarMonitorScopeId(for: workspaceMonitor),
                monitorName: availableMonitors.count > 1 ? workspaceMonitor.name : nil,
                isFocused: currentFocus.workspace == workspace,
                isVisible: workspace.isVisible,
                items: sidebarItems,
            ),
        )
    }

    let visibleSidebarWorkspaceNames = Set(sidebarWorkspaces.filter {
        workspaceSidebarWorkspaceMatchesScope(
            workspaceMonitorScopeId: $0.monitorScopeId,
            selectedScopeId: selectedMonitorScopeId,
            focusedMonitorScopeId: focusedMonitorScopeId,
        )
    }.map(\.name))

    let sanitizedHoveredWorkspaceName = sanitizedWorkspaceSidebarHoveredWorkspaceName(
        visibleWorkspaceNames: visibleSidebarWorkspaceNames,
        hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
    )
    if TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName != sanitizedHoveredWorkspaceName {
        TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = sanitizedHoveredWorkspaceName
    }
    let didMonitorScopeChange =
        TrayMenuModel.shared.workspaceSidebarMonitorScopes != monitorScopes ||
        TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId != selectedMonitorScopeId ||
        TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId != focusedMonitorScopeId ||
        TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector != (availableMonitors.count > 1)
    let didProjectChange =
        TrayMenuModel.shared.workspaceSidebarProjects != projects ||
            TrayMenuModel.shared.workspaceSidebarSelectedProjectId != selectedProjectId
    if TrayMenuModel.shared.workspaceSidebarProjects != projects {
        TrayMenuModel.shared.workspaceSidebarProjects = projects
    }
    if TrayMenuModel.shared.workspaceSidebarSelectedProjectId != selectedProjectId {
        TrayMenuModel.shared.workspaceSidebarSelectedProjectId = selectedProjectId
    }
    if TrayMenuModel.shared.workspaceSidebarMonitorScopes != monitorScopes {
        TrayMenuModel.shared.workspaceSidebarMonitorScopes = monitorScopes
    }
    if TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId != selectedMonitorScopeId {
        TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId = selectedMonitorScopeId
    }
    if TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId != focusedMonitorScopeId {
        TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId = focusedMonitorScopeId
    }
    if TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector != (availableMonitors.count > 1) {
        TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector = availableMonitors.count > 1
    }
    let didWorkspaceChange = TrayMenuModel.shared.workspaceSidebarWorkspaces != sidebarWorkspaces
    if didWorkspaceChange {
        TrayMenuModel.shared.workspaceSidebarWorkspaces = sidebarWorkspaces
    }
    if didWorkspaceChange || didTopPaddingChange || didMonitorScopeChange || didProjectChange || !WorkspaceSidebarPanel.shared.isVisible {
        WorkspaceSidebarPanel.shared.refresh()
    }
}

@MainActor
private func workspaceSidebarSelectedProjectMonitor(
    selectedScopeId: String,
    focusedMonitor: Monitor,
    sortedMonitors: [Monitor],
) -> Monitor {
    guard selectedScopeId != workspaceSidebarFocusedScopeId,
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
private func buildWorkspaceSidebarMonitorScopes(
    sortedMonitors: [Monitor],
    focusedMonitorScopeId: String,
) -> [WorkspaceSidebarMonitorScopeViewModel] {
    [
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

private func workspaceSidebarMonitorDisplayName(_ monitor: Monitor, fallbackIndex: Int) -> String {
    let name = monitor.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if monitor.isMain {
        return "Main"
    }
    return name.isEmpty ? "Display \(fallbackIndex)" : name
}

@MainActor
private func buildWorkspaceSidebarProjectViewModels() -> [WorkspaceSidebarProjectViewModel] {
    return workspaceProjects().map {
        WorkspaceSidebarProjectViewModel(
            id: $0.id,
            displayName: $0.name,
            colorHex: config.workspaceSidebar.projectColors[$0.id].flatMap(normalizedWorkspaceSidebarColorHex),
        )
    }
}

@MainActor
func sidebarDisplayLabel(for window: Window) -> String {
    let appName = window.app.name ?? window.app.rawAppBundleId ?? "Unknown App"
    return cachedWindowTitle(for: window)?.takeIf { $0 != appName } ?? appName
}

@MainActor
private func getSidebarWindowTitle(_ window: Window, appName: String) async -> String? {
    await getCachedWindowTitle(window)?.takeIf { $0 != appName }
}

@MainActor
private func buildWorkspaceSidebarItems(
    for workspace: Workspace,
    currentFocus: LiveFocus,
) async -> [WorkspaceSidebarItemViewModel] {
    var items = await buildWorkspaceSidebarItems(
        from: workspace.rootTilingContainer,
        workspaceName: workspace.name,
        currentFocus: currentFocus,
    )
    for floatingWindow in workspace.floatingWindows where floatingWindow.isBound {
        items.append(.init(kind: .window(await makeWorkspaceSidebarWindowViewModel(
            for: floatingWindow,
            workspaceName: workspace.name,
            currentFocus: currentFocus,
        ))))
    }
    return items
}

@MainActor
private func buildWorkspaceSidebarItems(
    from node: TreeNode,
    workspaceName: String,
    currentFocus: LiveFocus,
) async -> [WorkspaceSidebarItemViewModel] {
    switch node.nodeCases {
        case .window(let window):
            guard window.isBound else { return [] }
            return [.init(kind: .window(await makeWorkspaceSidebarWindowViewModel(
                for: window,
                workspaceName: workspaceName,
                currentFocus: currentFocus,
            )))]
        case .tilingContainer(let container):
            if container.layout == .accordion, container.children.count > 1 {
                let group = await makeWorkspaceSidebarTabGroupViewModel(
                    for: container,
                    workspaceName: workspaceName,
                    currentFocus: currentFocus,
                )
                return group.map { [.init(kind: .tabGroup($0))] } ?? []
            }
            var items: [WorkspaceSidebarItemViewModel] = []
            for child in container.children {
                items.append(contentsOf: await buildWorkspaceSidebarItems(
                    from: child,
                    workspaceName: workspaceName,
                    currentFocus: currentFocus,
                ))
            }
            return items
        case .workspace(let workspace):
            return await buildWorkspaceSidebarItems(
                from: workspace.rootTilingContainer,
                workspaceName: workspaceName,
                currentFocus: currentFocus,
            )
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return []
    }
}

@MainActor
private func makeWorkspaceSidebarTabGroupViewModel(
    for container: TilingContainer,
    workspaceName: String,
    currentFocus: LiveFocus,
) async -> WorkspaceSidebarTabGroupViewModel? {
    let representativeWindow = container.tabActiveWindow ?? container.mostRecentWindowRecursive ?? container.anyLeafWindowRecursive
    guard let representativeWindow else { return nil }
    var tabs: [WorkspaceSidebarWindowViewModel] = []
    for child in container.children {
        guard let representative = child.tabRepresentativeWindow ?? child.mostRecentWindowRecursive ?? child.anyLeafWindowRecursive,
              representative.isBound
        else { continue }
        tabs.append(await makeWorkspaceSidebarWindowViewModel(
            for: representative,
            workspaceName: workspaceName,
            currentFocus: currentFocus,
        ))
    }
    guard !tabs.isEmpty else { return nil }
    return WorkspaceSidebarTabGroupViewModel(
        representativeWindowId: representativeWindow.windowId,
        workspaceName: workspaceName,
        title: sidebarDisplayLabel(for: representativeWindow),
        windowCount: container.allLeafWindowsRecursive.count,
        isFocused: representativeWindow.moveNode == currentFocus.windowOrNil?.moveNode,
        tabs: tabs,
    )
}

@MainActor
private func makeWorkspaceSidebarWindowViewModel(
    for window: Window,
    workspaceName: String,
    currentFocus: LiveFocus,
) async -> WorkspaceSidebarWindowViewModel {
    let appName = window.app.name ?? window.app.rawAppBundleId ?? "Unknown App"
    let title = await getSidebarWindowTitle(window, appName: appName)
    return WorkspaceSidebarWindowViewModel(
        windowId: window.windowId,
        workspaceName: workspaceName,
        appName: appName,
        title: title,
        isFocused: currentFocus.windowOrNil == window,
    )
}
