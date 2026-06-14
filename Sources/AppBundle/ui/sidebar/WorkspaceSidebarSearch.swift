import Foundation

func workspaceSidebarFilteredWorkspacesByProject(
    _ workspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
    projects: [WorkspaceSidebarProjectViewModel],
    query: String,
) -> [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]] {
    let terms = workspaceSidebarSearchTerms(query)
    guard !terms.isEmpty else { return workspacesByProject }
    let projectNamesById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.displayName) })

    return workspacesByProject.mapValues { workspaces in
        workspaces.compactMap { workspace in
            workspaceSidebarFilteredWorkspace(
                workspace,
                projectName: projectNamesById[workspace.projectId],
                terms: terms,
            )
        }
    }
}

private func workspaceSidebarFilteredWorkspace(
    _ workspace: WorkspaceSidebarWorkspaceViewModel,
    projectName: String?,
    terms: [String],
) -> WorkspaceSidebarWorkspaceViewModel? {
    let matchingItems = workspace.items.compactMap { item in
        workspaceSidebarSearchResultItem(item, workspace: workspace, projectName: projectName, terms: terms)
    }
    if !matchingItems.isEmpty {
        return WorkspaceSidebarWorkspaceViewModel(
            name: workspace.name,
            projectId: workspace.projectId,
            displayName: workspace.displayName,
            sidebarLabel: workspace.sidebarLabel,
            isGeneratedName: workspace.isGeneratedName,
            monitorScopeId: workspace.monitorScopeId,
            monitorName: workspace.monitorName,
            isFocused: workspace.isFocused,
            isVisible: workspace.isVisible,
            items: matchingItems,
        )
    }
    if workspaceSidebarWorkspaceMatchesSearch(workspace, projectName: projectName, terms: terms) {
        return workspace
    }
    return nil
}

private func workspaceSidebarSearchTerms(_ query: String) -> [String] {
    query
        .split(whereSeparator: { $0.isWhitespace })
        .map { String($0).localizedLowercase }
        .filter { !$0.isEmpty }
}

private func workspaceSidebarSearchResultItem(
    _ item: WorkspaceSidebarItemViewModel,
    workspace: WorkspaceSidebarWorkspaceViewModel,
    projectName: String?,
    terms: [String],
) -> WorkspaceSidebarItemViewModel? {
    switch item.kind {
        case .window(let window):
            if workspaceSidebarSearchTextMatches(
                [
                    window.title,
                    window.appName,
                    window.appBundleId,
                    window.appBundlePath,
                    workspace.displayName,
                    workspace.name,
                    projectName,
                ],
                terms: terms,
            ) {
                return item
            }
            return nil
        case .tabGroup(let group):
            let matchingTabs = group.tabs.filter { tab in
                workspaceSidebarSearchTextMatches(
                    [tab.title, tab.appName, tab.appBundleId, tab.appBundlePath, workspace.displayName, workspace.name, projectName],
                    terms: terms,
                )
            }
            if !matchingTabs.isEmpty {
                return WorkspaceSidebarItemViewModel(kind: .tabGroup(WorkspaceSidebarTabGroupViewModel(
                    representativeWindowId: group.representativeWindowId,
                    workspaceName: group.workspaceName,
                    title: group.title,
                    windowCount: group.windowCount,
                    isFocused: group.isFocused,
                    tabs: group.tabs,
                    searchVisibleTabs: matchingTabs,
                )))
            }
            guard workspaceSidebarSearchTextMatches(
                [
                    group.title,
                    workspace.displayName,
                    workspace.name,
                    projectName,
                ],
                terms: terms,
            ) else {
                return nil
            }
            return WorkspaceSidebarItemViewModel(kind: .tabGroup(WorkspaceSidebarTabGroupViewModel(
                representativeWindowId: group.representativeWindowId,
                workspaceName: group.workspaceName,
                title: group.title,
                windowCount: group.windowCount,
                isFocused: group.isFocused,
                tabs: group.tabs,
                searchVisibleTabs: [],
            )))
    }
}

private func workspaceSidebarWorkspaceMatchesSearch(
    _ workspace: WorkspaceSidebarWorkspaceViewModel,
    projectName: String?,
    terms: [String],
) -> Bool {
    workspaceSidebarSearchTextMatches(
        [
            workspace.displayName,
            workspace.sidebarLabel,
            workspace.name,
            workspace.monitorName,
            projectName,
        ],
        terms: terms,
    )
}

private func workspaceSidebarSearchTextMatches(_ values: [String?], terms: [String]) -> Bool {
    let searchableText = values
        .compactMap { $0?.localizedLowercase }
        .joined(separator: " ")
    return terms.allSatisfy { searchableText.contains($0) }
}
