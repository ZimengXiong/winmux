import CoreGraphics

struct WindowTabGroupChromeContent: Equatable {
    let workspaceName: String
    let activeWindowId: UInt32?
    let activeWindowCornerRadius: CGFloat
    let tabs: [WindowTabItemViewModel]
    let occludingFloatingWindowFrames: [CGRect]
    let drawsMockTabs: Bool

    init(strip: WindowTabStripViewModel, drawsMockTabs: Bool = false) {
        workspaceName = strip.workspaceName
        activeWindowId = strip.activeWindowId
        activeWindowCornerRadius = strip.activeWindowCornerRadius
        tabs = strip.tabs
        occludingFloatingWindowFrames = strip.occludingFloatingWindowFrames
        self.drawsMockTabs = drawsMockTabs
    }
}
