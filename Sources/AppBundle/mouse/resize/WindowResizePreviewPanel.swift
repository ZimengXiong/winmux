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

    func show(
        _ screenItems: [WindowResizePreviewItem],
        presentation: WindowResizePreviewPresentation = .detailed,
    ) {
        pendingHide?.cancel()
        pendingHide = nil
        guard let panelFrame = stableFrame ?? windowResizePreviewPanelFrame(for: screenItems) else {
            logWindowDragLive("resizePreview show aborted: no panel frame itemCount=\(screenItems.count)")
            hide(reason: "show.no-panel-frame")
            return
        }

        let wasVisible = isVisible
        let alignedPanelFrame = panelFrame.alignedToBackingPixels()
        let localItems = screenItems.map { $0.localItem(in: alignedPanelFrame) }
        if frame.size == alignedPanelFrame.size {
            setFrameOrigin(alignedPanelFrame.origin)
        } else {
            setFrame(alignedPanelFrame, display: false, animate: false)
        }
        compositorView.update(localItems, presentation: presentation)
        if !isVisible {
            orderFrontRegardless()
        }
        logWindowDragLive(
            "resizePreview show itemCount=\(screenItems.count) wasVisible=\(wasVisible) isVisible=\(isVisible) level=\(level.rawValue) frame=\(frame)"
        )
    }

    func hide(reason: String, after delay: TimeInterval = 0) {
        pendingHide?.cancel()
        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let wasVisible = self.isVisible
            self.pendingHide = nil
            self.compositorView.clear()
            if self.isVisible {
                self.orderOut(nil)
            }
            if wasVisible {
                logWindowDragLive("resizePreview hide reason=\(reason) wasVisible=\(wasVisible) isVisible=\(self.isVisible) mouseDown=\(isLeftMouseButtonDown) manipulated=\(currentlyManipulatedWithMouseWindowId?.description ?? "nil") kind=\(getCurrentMouseManipulationKind())")
            }
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
    func localItem(in panelFrame: CGRect) -> WindowResizePreviewItem {
        WindowResizePreviewItem(
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
