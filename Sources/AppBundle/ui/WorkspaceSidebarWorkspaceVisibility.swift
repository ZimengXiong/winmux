func workspaceSidebarShowsCreateWorkspace(selectedScopeId: String) -> Bool {
    selectedScopeId != workspaceSidebarFocusedScopeId &&
        selectedScopeId != workspaceSidebarAllScopeId
}
