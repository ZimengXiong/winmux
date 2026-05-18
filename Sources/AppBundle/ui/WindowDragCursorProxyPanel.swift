import AppKit
import Common
import SwiftUI

@MainActor
final class WindowDragCursorProxyPanel: NSPanelHud {
    static let shared = WindowDragCursorProxyPanel()

    let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    var currentContent: WindowDragCursorProxyContent?
    var proxySize: CGSize = .zero

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowDragCursorProxyPanelId)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        backgroundColor = .clear
        applyWinMuxLayer(.dragCursorProxy)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func show(label: String, isGroup: Bool, mouseScreenPoint: CGPoint) {
        updateContent(label: label, isGroup: isGroup)
        proxySize = windowDragCursorProxySize(label: label)
        updateFrame(mouseScreenPoint: mouseScreenPoint)
        startFollowingMouseIfNeeded()
        orderFrontRegardless()
    }

    func hide() {
        stopFollowingMouse()
        currentContent = nil
        orderOut(nil)
    }
}
