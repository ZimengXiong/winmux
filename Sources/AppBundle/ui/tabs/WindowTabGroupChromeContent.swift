import CoreGraphics

struct WindowTabGroupChromeContent: Equatable {
    let workspaceName: String
    let activeWindowId: UInt32?
    let activeWindowCornerRadius: CGFloat
    let tabs: [WindowTabItemViewModel]
    let occludingFloatingWindowFrames: [CGRect]
    let chromeStyle: ChromeStyle
    let solidChromeColor: ChromeSolidColor

    @MainActor init(strip: WindowTabStripViewModel) {
        workspaceName = strip.workspaceName
        activeWindowId = strip.activeWindowId
        activeWindowCornerRadius = strip.activeWindowCornerRadius
        tabs = strip.tabs
        occludingFloatingWindowFrames = strip.occludingFloatingWindowFrames
        chromeStyle = config.workspaceSidebar.chromeStyle
        solidChromeColor = config.workspaceSidebar.solidChromeColor
    }
}
