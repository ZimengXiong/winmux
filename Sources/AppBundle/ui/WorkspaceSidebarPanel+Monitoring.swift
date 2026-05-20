import AppKit

extension WorkspaceSidebarPanel {
    func startHoverMonitoring() {
        guard !isHoverMonitoring else { return }
        isHoverMonitoring = true
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] timestamp in
            guard let self else { return }
            guard timestamp - self.lastHoverMonitorTimestamp >= self.hoverPollInterval else { return }
            self.lastHoverMonitorTimestamp = timestamp
            self.updateHoverStateFromMousePosition()
        }
    }

    func stopHoverMonitoring() {
        cancelExpansionWork()
        isHoverMonitoring = false
        lastHoverMonitorTimestamp = 0
        DisplayRefreshDriver.shared.remove(owner: self)
    }

    func updateHoverStateFromMousePosition() {
        trapCursorForLeftEdgeSidebarActivationIfNeeded()
        updateMousePassthrough()
        setHovering(isMouseInsideHoverRegion())
    }
}
