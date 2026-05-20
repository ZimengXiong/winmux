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
        let activeZone = model.activeZone?.rawValue ?? "nil"
        guard let frame = Self.panelFrame(for: model.targetFrame)?.alignedToBackingPixels() else {
            logWindowDragLive("dropOverlay show aborted: no panel frame target=\(debugDescribe(model.targetFrame)) zone=\(activeZone)")
            hide()
            return
        }
        let wasVisible = panel.isVisible
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
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        logWindowDragLive(
            "dropOverlay show zone=\(activeZone) wasVisible=\(wasVisible) isVisible=\(panel.isVisible) level=\(panel.level.rawValue) frame=\(panel.frame) target=\(debugDescribe(model.targetFrame))"
        )
    }

    func hide() {
        guard currentModel != nil || panel.isVisible else { return }
        let wasVisible = panel.isVisible
        hostingView.rootView = AnyView(EmptyView())
        currentModel = nil
        if panel.isVisible {
            panel.orderOut(nil)
        }
        logWindowDragLive("dropOverlay hide wasVisible=\(wasVisible) isVisible=\(panel.isVisible)")
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
