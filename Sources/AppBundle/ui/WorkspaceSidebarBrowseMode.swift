import Common

enum WorkspaceSidebarBrowseMode: Equatable {
    case activeProject
    case split(otherProjectId: WorkspaceProjectId)

    var otherProjectId: WorkspaceProjectId? {
        switch self {
            case .activeProject:
                nil
            case .split(let projectId):
                projectId
        }
    }

    var isSplit: Bool {
        otherProjectId != nil
    }
}
