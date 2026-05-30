import AppKit

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
