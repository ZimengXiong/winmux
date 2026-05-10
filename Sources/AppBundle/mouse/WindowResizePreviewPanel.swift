import AppKit
import Common

@MainActor
final class WindowResizePreviewPanel: NSPanelHud {
    static let shared = WindowResizePreviewPanel()

    private let compositorView = WindowResizePreviewCompositorView()
    private var pendingHide: DispatchWorkItem? = nil
    private var stableFrame: CGRect? = nil

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier("WinMux.resizePreview")
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        backgroundColor = .clear
        applyWinMuxLayer(.overlay)

        compositorView.frame = contentView?.bounds ?? .zero
        compositorView.autoresizingMask = [.width, .height]
        contentView = compositorView
    }

    func beginStableFrame(_ frame: CGRect) {
        stableFrame = frame.alignedToBackingPixels()
    }

    func endStableFrame() {
        stableFrame = nil
    }

    func show(_ screenItems: [WindowResizePreviewItem]) {
        pendingHide?.cancel()
        pendingHide = nil
        guard let panelFrame = stableFrame ?? windowResizePreviewPanelFrame(for: screenItems) else {
            hide()
            return
        }

        let alignedPanelFrame = panelFrame.alignedToBackingPixels()
        let localItems = screenItems.map { $0.localItem(in: alignedPanelFrame) }
        if frame.size == alignedPanelFrame.size {
            setFrameOrigin(alignedPanelFrame.origin)
        } else {
            setFrame(alignedPanelFrame, display: false, animate: false)
        }
        compositorView.update(localItems)
        if !isVisible {
            orderFrontRegardless()
        }
    }

    func hide(after delay: TimeInterval = 0) {
        pendingHide?.cancel()
        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            self.compositorView.clear()
            self.orderOut(nil)
        }
        pendingHide = hideWorkItem
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: hideWorkItem)
        } else {
            hideWorkItem.perform()
        }
    }
}

private extension WindowResizePreviewItem {
    func localItem(in panelFrame: CGRect) -> WindowResizePreviewLocalItem {
        WindowResizePreviewLocalItem(
            id: id,
            frame: CGRect(
                x: frame.minX - panelFrame.minX,
                y: panelFrame.maxY - frame.maxY,
                width: frame.width,
                height: frame.height,
            ),
            appName: appName,
            icons: icons,
            isTabGroup: isTabGroup,
            drawsFrameOnly: drawsFrameOnly,
            frameOnlyHeaderHeight: frameOnlyHeaderHeight,
        )
    }
}

private func windowResizePreviewPanelFrame(for items: [WindowResizePreviewItem]) -> CGRect? {
    guard let firstFrame = items.first?.frame else { return nil }
    let union = items.dropFirst().reduce(firstFrame) { $0.union($1.frame) }
    return union.insetBy(dx: -8, dy: -8)
}
