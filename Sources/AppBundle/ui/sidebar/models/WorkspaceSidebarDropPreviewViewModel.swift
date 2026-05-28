struct WorkspaceSidebarDropPreviewTabItem: Hashable {
    let title: String
    let appName: String
    let appBundleIdentifier: String?
    let appBundlePath: String?
}

struct WorkspaceSidebarDropPreviewViewModel: Hashable {
    let sourceWindowId: UInt32
    let label: String
    let appName: String
    let appBundleIdentifier: String?
    let appBundlePath: String?
    let targetWorkspaceName: String?
    let targetsNewWorkspace: Bool
    let targetProjectId: WorkspaceProjectId?
    let isTabGroup: Bool
    let windowCount: Int
    let tabItems: [WorkspaceSidebarDropPreviewTabItem]

    init(
        sourceWindowId: UInt32,
        label: String,
        appName: String,
        appBundleIdentifier: String? = nil,
        appBundlePath: String? = nil,
        targetWorkspaceName: String?,
        targetsNewWorkspace: Bool,
        targetProjectId: WorkspaceProjectId? = nil,
        isTabGroup: Bool,
        windowCount: Int,
        tabItems: [WorkspaceSidebarDropPreviewTabItem] = []
    ) {
        self.sourceWindowId = sourceWindowId
        self.label = label
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.appBundlePath = appBundlePath
        self.targetWorkspaceName = targetWorkspaceName
        self.targetsNewWorkspace = targetsNewWorkspace
        self.targetProjectId = targetProjectId
        self.isTabGroup = isTabGroup
        self.windowCount = windowCount
        self.tabItems = tabItems
    }
}
