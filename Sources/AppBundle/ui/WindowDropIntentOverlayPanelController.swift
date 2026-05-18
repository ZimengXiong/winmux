import AppKit
import Common
import SwiftUI

@MainActor
final class WindowDropIntentOverlayPanelController {
    static let shared = WindowDropIntentOverlayPanelController()

    private let panel = NSPanelHud()
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var currentModel: WindowDropIntentOverlayModel?

    private init() {
        panel.identifier = NSUserInterfaceItemIdentifier("WinMux.windowDropIntent")
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.applyWinMuxLayer(.windowIntentPreview)
        panel.contentView = hostingView
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    var isVisible: Bool {
        panel.isVisible
    }

    var level: NSWindow.Level {
        panel.level
    }

    func show(_ model: WindowDropIntentOverlayModel) {
        guard let frame = Self.panelFrame(for: model.targetFrame)?.alignedToBackingPixels() else {
            hide()
            return
        }
        if panel.frame.size == frame.size {
            panel.setFrameOrigin(frame.origin)
        } else {
            panel.setFrame(frame, display: false, animate: false)
        }
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        if currentModel != model || !panel.isVisible {
            hostingView.rootView = AnyView(WindowDropIntentOverlayView(model: model))
            currentModel = model
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        hostingView.rootView = AnyView(EmptyView())
        currentModel = nil
        panel.orderOut(nil)
    }

    private static func panelFrame(for frame: Rect) -> CGRect? {
        let rect = frame.toAppKitScreenRect
        let candidates = NSScreen.screens.compactMap { screen -> (CGRect, CGFloat)? in
            let intersection = rect.intersection(screen.frame)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
                return nil
            }
            return (rect, intersection.width * intersection.height)
        }
        return candidates.max { $0.1 < $1.1 }?.0
    }
}
