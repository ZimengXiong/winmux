struct WorkspaceSidebarDropPreviewViewModel: Hashable {
    let sourceWindowId: UInt32
    let label: String
    let targetWorkspaceName: String?
    let targetsNewWorkspace: Bool
    let isTabGroup: Bool
    let windowCount: Int
}
