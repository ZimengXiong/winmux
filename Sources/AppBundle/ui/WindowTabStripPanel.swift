import AppKit
import Common
import SwiftUI

@MainActor
final class WindowTabStripPanel: NSPanelHud {
    let hostingView = WindowTabStripHostingView(rootView: AnyView(EmptyView()))
    var currentContent: WindowTabGroupChromeContent?
    var currentPanelFrame: CGRect?
    var externallyIgnoresMouseEvents = false
    var tabStripIsOccludedByFloatingWindow = false

    init(id: ObjectIdentifier) {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowTabStripPanelPrefix + String(id.hashValue))
        hasShadow = false
        isFloatingPanel = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = .clear
        applyWinMuxLayer(.windowChrome)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func update(with strip: WindowTabStripViewModel) {
        let displayStrip = strip.alignedForWindowTabChrome()
        let nextContent = WindowTabGroupChromeContent(strip: displayStrip)
        guard shouldUpdate(content: nextContent, strip: displayStrip) else { return }
        if currentContent != nextContent {
            hostingView.rootView = AnyView(WindowTabStripView(strip: displayStrip))
            currentContent = nextContent
        }
        currentPanelFrame = displayStrip.frame
        debugFocusLog("WindowTabStripPanel.update id=\(String(describing: identifier?.rawValue)) frame=\(displayStrip.frame)")
        setWindowTabChromePanelFrame(displayStrip.frame, on: self)
        tabStripIsOccludedByFloatingWindow = displayStrip.tabStripIsOccludedByFloatingWindow
        updateMousePolicy()
        applyWindowTabStripStackingPolicy(for: displayStrip, to: self)
    }

    func setExternalIgnoresMouseEvents(_ ignoresMouseEvents: Bool) {
        externallyIgnoresMouseEvents = ignoresMouseEvents
        updateMousePolicy()
    }
}
