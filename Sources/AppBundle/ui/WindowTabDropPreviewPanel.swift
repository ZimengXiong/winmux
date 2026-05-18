import AppKit
import Common
import SwiftUI

@MainActor
final class WindowTabDropPreviewPanel: NSPanelHud {
    static let shared = WindowTabDropPreviewPanel()

    let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    var hasShownPreview = false
    var currentPreviewKey: WindowIntentPreviewContentKey?

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowTabDropPreviewPanelId)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        backgroundColor = .clear
        // Keep window intent previews above app windows but below the sidebar,
        // because the hints target windows behind that sidebar.
        applyWinMuxLayer(.windowIntentPreview)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func show(_ preview: WindowTabDropPreviewViewModel) {
        let targetFrame = preview.containerFrame.alignedToBackingPixels()
        if frame.size == targetFrame.size {
            setFrameOrigin(targetFrame.origin)
        } else {
            setFrame(targetFrame, display: false, animate: false)
        }
        hostingView.frame = CGRect(origin: .zero, size: targetFrame.size)
        alphaValue = 1
        let previewKey = WindowIntentPreviewContentKey(model: preview)
        if currentPreviewKey != previewKey || !hasShownPreview {
            hostingView.rootView = AnyView(WindowIntentPreviewOverlayView(model: preview))
            currentPreviewKey = previewKey
        }
        if !isVisible || !hasShownPreview {
            orderFrontRegardless()
        }
        hasShownPreview = true
    }

    func hide() {
        hostingView.rootView = AnyView(EmptyView())
        hasShownPreview = false
        currentPreviewKey = nil
        alphaValue = 1
        orderOut(nil)
    }
}
