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
        level = NSWindow.Level(rawValue: WinMuxPanelLayer.workspaceSidebar.level.rawValue + 1)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func show(label: String, isGroup: Bool, mouseScreenPoint: CGPoint) {
        updateContent(label: label, isGroup: isGroup)
        proxySize = windowDragCursorProxySize(label: label)
        updateFrame(mouseScreenPoint: mouseScreenPoint)
        startFollowingMouseIfNeeded()
        if !isVisible {
            orderFrontRegardless()
        }
    }

    func show(preview: WorkspaceSidebarDropPreviewViewModel, mouseScreenPoint: CGPoint) {
        updateContent(preview: preview)
        proxySize = windowDragCursorProxySize(label: preview.label)
        updateFrame(mouseScreenPoint: mouseScreenPoint)
        startFollowingMouseIfNeeded()
        if !isVisible {
            orderFrontRegardless()
        }
    }

    func hide() {
        guard currentContent != nil || isVisible else { return }
        stopFollowingMouse()
        currentContent = nil
        if isVisible {
            orderOut(nil)
        }
    }
}
struct WindowDragCursorProxyContent: Equatable {
    let label: String
    let isGroup: Bool
    let preview: WorkspaceSidebarDropPreviewViewModel?

    init(label: String, isGroup: Bool, preview: WorkspaceSidebarDropPreviewViewModel? = nil) {
        self.label = label
        self.isGroup = isGroup
        self.preview = preview
    }
}

extension WindowDragCursorProxyPanel {
    func updateContent(label: String, isGroup: Bool) {
        let nextContent = WindowDragCursorProxyContent(label: label, isGroup: isGroup)
        guard currentContent != nextContent else { return }
        hostingView.rootView = AnyView(WindowDragCursorProxyView(label: label, isGroup: isGroup))
        currentContent = nextContent
    }

    func updateContent(preview: WorkspaceSidebarDropPreviewViewModel) {
        let nextContent = WindowDragCursorProxyContent(
            label: preview.label,
            isGroup: preview.isTabGroup,
            preview: preview,
        )
        guard currentContent != nextContent else { return }
        hostingView.rootView = AnyView(WindowDragCursorProxyView(preview: preview))
        currentContent = nextContent
    }
}

func windowDragCursorProxySize(label: String) -> CGSize {
    CGSize(width: min(max(CGFloat(label.count) * 7 + 42, 96), 224), height: 28)
}
extension WindowDragCursorProxyPanel {
    func startFollowingMouseIfNeeded() {
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in
            self?.updateFrameWhileDragging(mouseScreenPoint: NSEvent.mouseLocation)
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

    private func updateFrameWhileDragging(mouseScreenPoint: CGPoint) {
        guard isLeftMouseButtonDown else {
            hide()
            return
        }
        updateFrame(mouseScreenPoint: mouseScreenPoint)
    }
}
