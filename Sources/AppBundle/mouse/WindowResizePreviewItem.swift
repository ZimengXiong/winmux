import AppKit
import Common

struct WindowResizePreviewItem: Identifiable, Equatable {
    let id: UInt32
    let frame: CGRect
    let appName: String
    let icons: [WindowResizePreviewIcon]
    let isTabGroup: Bool
    let drawsFrameOnly: Bool
    let frameOnlyHeaderHeight: CGFloat
}

struct WindowResizePreviewIcon: Hashable {
    let appName: String
    let appBundleId: String?
    let appBundlePath: String?
}

extension WindowResizePreviewIcon {
    @MainActor
    init(window: Window) {
        self.init(
            appName: window.app.name ?? window.app.rawAppBundleId ?? "Window",
            appBundleId: window.app.rawAppBundleId,
            appBundlePath: window.app.bundlePath,
        )
    }
}
