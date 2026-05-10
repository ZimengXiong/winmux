import AppKit
import Common
import SwiftUI

@MainActor
final class WindowTabDropPreviewPanel: NSPanelHud {
    static let shared = WindowTabDropPreviewPanel()

    let compositorView = WindowIntentPreviewCompositorView()
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
        contentView = compositorView
        compositorView.frame = contentView?.bounds ?? .zero
        compositorView.autoresizingMask = [.width, .height]
    }

    func show(_ preview: WindowTabDropPreviewViewModel) {
        let targetFrame = preview.containerFrame.alignedToBackingPixels()
        if frame.size == targetFrame.size {
            setFrameOrigin(targetFrame.origin)
        } else {
            setFrame(targetFrame, display: false, animate: false)
        }
        compositorView.frame = CGRect(origin: .zero, size: targetFrame.size)
        alphaValue = 1
        let previewKey = WindowIntentPreviewContentKey(model: preview)
        if currentPreviewKey != previewKey || !hasShownPreview {
            let animation: WindowIntentPreviewAnimation
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                animation = .none
            } else if hasShownPreview, currentPreviewKey?.canMorph(to: previewKey) == true {
                animation = .morph
            } else if !hasShownPreview {
                animation = .appear
            } else {
                animation = .none
            }
            compositorView.update(preview, animation: animation)
            currentPreviewKey = previewKey
        }
        if !isVisible || !hasShownPreview {
            orderFrontRegardless()
        }
        hasShownPreview = true
    }

    func hide() {
        compositorView.clear()
        hasShownPreview = false
        currentPreviewKey = nil
        alphaValue = 1
        orderOut(nil)
    }
}

// MARK: - Cursor Drag Proxy (follows cursor during sidebar-originated drags)

@MainActor
final class WindowDragCursorProxyPanel: NSPanelHud {
    static let shared = WindowDragCursorProxyPanel()

    let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    var currentContent: WindowDragCursorProxyContent? = nil
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
        let nextContent = WindowDragCursorProxyContent(label: label, isGroup: isGroup)
        if currentContent != nextContent {
            hostingView.rootView = AnyView(WindowDragCursorProxyView(label: label, isGroup: isGroup))
            currentContent = nextContent
        }
        proxySize = CGSize(
            width: min(max(CGFloat(label.count) * 7 + 36, 80), 200),
            height: 28,
        )
        updateFrame(mouseScreenPoint: mouseScreenPoint)
        startFollowingMouseIfNeeded()
        orderFrontRegardless()
    }

    func hide() {
        stopFollowingMouse()
        currentContent = nil
        orderOut(nil)
    }

    func startFollowingMouseIfNeeded() {
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in
            self?.updateFrame(mouseScreenPoint: NSEvent.mouseLocation)
        }
    }

    func stopFollowingMouse() {
        DisplayRefreshDriver.shared.remove(owner: self)
    }

    func updateFrame(mouseScreenPoint: CGPoint) {
        guard proxySize.width > 0, proxySize.height > 0 else { return }
        let targetFrame = windowDragCursorProxyFrame(
            mouseScreenPoint: mouseScreenPoint,
            proxySize: proxySize,
        )
        if frame.size == targetFrame.size {
            setFrameOrigin(targetFrame.origin)
        } else {
            setFrame(targetFrame, display: false, animate: false)
        }
    }
}

struct WindowDragCursorProxyContent: Equatable {
    let label: String
    let isGroup: Bool
}

func windowDragCursorProxyFrame(mouseScreenPoint: CGPoint, proxySize: CGSize) -> CGRect {
    let screenFrame = NSScreen.screens
        .first(where: { $0.frame.contains(mouseScreenPoint) })?
        .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

    var x = mouseScreenPoint.x + 14
    var y = mouseScreenPoint.y - proxySize.height - 6

    if x + proxySize.width > screenFrame.maxX {
        x = mouseScreenPoint.x - proxySize.width - 14
    }
    if y < screenFrame.minY {
        y = mouseScreenPoint.y + 6
    }

    return CGRect(
        x: x,
        y: y,
        width: proxySize.width,
        height: proxySize.height,
    )
}

struct WindowDragCursorProxyView: View {
    let label: String
    let isGroup: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isGroup ? "square.stack" : "macwindow")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(mattePanelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(mattePanelSeparator, lineWidth: 0.7)
                }
                .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2),
        )
    }
}

