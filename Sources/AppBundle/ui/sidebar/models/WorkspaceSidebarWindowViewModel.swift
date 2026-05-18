struct WorkspaceSidebarWindowViewModel: Hashable, Identifiable {
    let windowId: UInt32
    let workspaceName: String
    let appName: String
    let appBundleId: String?
    let appBundlePath: String?
    let title: String?
    let isFocused: Bool

    var id: UInt32 { windowId }
}

struct WorkspaceSidebarTabGroupViewModel: Hashable, Identifiable {
    let representativeWindowId: UInt32
    let workspaceName: String
    let title: String
    let windowCount: Int
    let isFocused: Bool
    let tabs: [WorkspaceSidebarWindowViewModel]

    var id: String { "group:\(representativeWindowId)" }
}
