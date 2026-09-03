import Foundation

let sidebarDraftWorkspacePrefix = "__sidebar_draft_workspace_"
let internalAutomaticWorkspacePrefix = "__internal_auto_workspace_"
let workspaceProjectDefaultId = WorkspaceProjectId.defaultProject

struct WorkspaceProject: Hashable, Identifiable {
    let id: WorkspaceProjectId
    let name: String
    let order: Int
    var workspaceOrder: [WorkspaceId] = []
    var linkedViewportIds: Set<MonitorViewportId> = []
}

enum WorkspaceMutationError: LocalizedError {
    case workspaceNotFound(String)
    case workspaceCannotBeDeleted(String)
    case projectNotFound(String)
    case projectCannotBeDeleted(String)
    case projectCloseBlocked(String, Int)
    case invalidProjectColor(String)
    case emptyName
    case nameContainsControlCharacters
    case duplicateProjectName(String)

    var errorDescription: String? {
        switch self {
            case .workspaceNotFound(let name):
                "Workspace '\(name)' no longer exists."
            case .workspaceCannotBeDeleted(let name):
                "Workspace '\(name)' cannot be deleted."
            case .projectNotFound(let id):
                "Project '\(id)' no longer exists."
            case .projectCannotBeDeleted(let name):
                "Project '\(name)' cannot be deleted."
            case .projectCloseBlocked(let name, let count):
                "Project '\(name)' was not deleted because \(count) window\(count == 1 ? "" : "s") stayed open."
            case .invalidProjectColor(let color):
                "Invalid project color '\(color)'. Expected 'auto' or a six-digit hex color such as '#1A2B3C'."
            case .emptyName:
                "Name cannot be empty."
            case .nameContainsControlCharacters:
                "Name cannot contain control characters."
            case .duplicateProjectName(let name):
                "A project named '\(name)' already exists."
        }
    }
}

enum WorkspaceNamingStyle: String, Codable, Sendable {
    case explicit
    case automatic
}
