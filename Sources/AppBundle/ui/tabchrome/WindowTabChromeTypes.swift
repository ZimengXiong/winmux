import CoreGraphics

struct WindowTabChromeTabItem: Equatable, Identifiable {
    let id: UInt32
    let title: String
    let appName: String
    let appBundleIdentifier: String?
    let isActive: Bool
}

struct WindowTabChromeItem: Equatable, Identifiable {
    let id: ObjectIdentifier
    let workspaceName: String
    let activeWindowId: UInt32
    let orderingWindowId: UInt32
    let contentFrame: CGRect
    let visibleFrame: CGRect?
    let tabs: [WindowTabChromeTabItem]
}
