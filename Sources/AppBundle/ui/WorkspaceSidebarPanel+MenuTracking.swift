import AppKit

extension WorkspaceSidebarPanel {
    func installMenuTrackingObservers() {
        let center = NotificationCenter.default
        menuTrackingObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.beginMenuTrackingIfNeeded() }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.endMenuTrackingIfNeeded() }
            },
        ]
    }

    func beginMenuTrackingIfNeeded() {
        guard isVisible,
              viewModel.workspaceSidebarVisibleWidth > 0
        else { return }
        menuTrackingDepth += 1
        menuTrackingGraceUntil = .distantFuture
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
        expandSidebar(to: CGFloat(config.workspaceSidebar.width))
    }

    func endMenuTrackingIfNeeded() {
        guard menuTrackingDepth > 0 else { return }
        menuTrackingDepth -= 1
        guard menuTrackingDepth == 0 else { return }
        menuTrackingGraceUntil = Date().addingTimeInterval(menuTrackingEndGrace)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.updateHoverStateFromMousePosition()
        }
    }

    func isMenuTrackingOrInGracePeriod(now: Date = .now) -> Bool {
        menuTrackingDepth > 0 || now < menuTrackingGraceUntil
    }
}
