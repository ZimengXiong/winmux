import AppKit

struct WorkspaceSidebarTransientState: Equatable {
    let hoveredWorkspaceName: String?
}

func sanitizedWorkspaceSidebarTransientState(
    visibleWorkspaceNames: Set<String>,
    state: WorkspaceSidebarTransientState,
) -> WorkspaceSidebarTransientState {
    let hoveredWorkspaceName =
        state.hoveredWorkspaceName != nil && visibleWorkspaceNames.contains(state.hoveredWorkspaceName.orDie())
            ? state.hoveredWorkspaceName
            : nil
    return WorkspaceSidebarTransientState(
        hoveredWorkspaceName: hoveredWorkspaceName,
    )
}

@MainActor
func updateWorkspaceSidebarModel() async {
    guard TrayMenuModel.shared.isEnabled, config.workspaceSidebar.enabled else {
        if !TrayMenuModel.shared.workspaceSidebarWorkspaces.isEmpty {
            TrayMenuModel.shared.workspaceSidebarWorkspaces = []
        }
        WorkspaceSidebarPanel.shared.refresh()
        return
    }

    let currentFocus = focus
    let workspaceLabels = config.workspaceSidebar.workspaceLabels
    let previousTopPadding = TrayMenuModel.shared.workspaceSidebarTopPadding
    pruneCachedWindowTitles()

    let gaps = ResolvedGaps(gaps: config.gaps, monitor: mainMonitor)
    TrayMenuModel.shared.workspaceSidebarTopPadding = CGFloat(gaps.outer.top)
    let didTopPaddingChange = TrayMenuModel.shared.workspaceSidebarTopPadding != previousTopPadding

    var sidebarWorkspaces: [WorkspaceSidebarWorkspaceViewModel] = []
    for workspace in Workspace.all {
        if !shouldShowWorkspaceInSidebar(workspace, currentFocus: currentFocus, isEditingWorkspace: false) {
            continue
        }
        let sidebarItems = await buildWorkspaceSidebarItems(for: workspace, currentFocus: currentFocus)

        let sidebarLabel = workspaceLabels[workspace.name] ?? ""
        let isGeneratedName = isSidebarDraftWorkspaceName(workspace.name)
        let displayName = workspaceDisplayName(workspace.name)

        sidebarWorkspaces.append(
            WorkspaceSidebarWorkspaceViewModel(
                name: workspace.name,
                displayName: displayName,
                sidebarLabel: sidebarLabel,
                isGeneratedName: isGeneratedName,
                monitorName: nil,
                isFocused: currentFocus.workspace == workspace,
                isVisible: workspace.isVisible,
                items: sidebarItems,
            ),
        )
    }

    let sanitizedTransientState = sanitizedWorkspaceSidebarTransientState(
        visibleWorkspaceNames: Set(sidebarWorkspaces.map(\.name)),
        state: WorkspaceSidebarTransientState(
            hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
        ),
    )
    if TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName != sanitizedTransientState.hoveredWorkspaceName {
        TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = sanitizedTransientState.hoveredWorkspaceName
    }
    let didWorkspaceChange = TrayMenuModel.shared.workspaceSidebarWorkspaces != sidebarWorkspaces
    if didWorkspaceChange {
        TrayMenuModel.shared.workspaceSidebarWorkspaces = sidebarWorkspaces
    }
    if didWorkspaceChange || didTopPaddingChange || !WorkspaceSidebarPanel.shared.isVisible {
        WorkspaceSidebarPanel.shared.refresh()
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
