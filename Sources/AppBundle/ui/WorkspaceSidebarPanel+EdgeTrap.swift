import AppKit

extension WorkspaceSidebarPanel {
    static func trapCursorForVisiblePanelsIfNeeded() {
        for panel in visiblePanels {
            panel.trapCursorForLeftEdgeSidebarActivationIfNeeded()
        }
    }

    func trapCursorForLeftEdgeSidebarActivationIfNeeded() {
        guard isVisible,
              config.workspaceSidebar.enabled,
              !currentSessionModifierFlags().contains(.maskShift),
              !isMouseWindowDragInProgress(),
              !isWorkspaceSidebarItemDragActive(),
              viewModel.workspaceSidebarVisibleWidth <= CGFloat(config.workspaceSidebar.collapsedWidth) + 0.5
        else {
            edgeTrapStartedAt = nil
            lastEdgeTrapSample = MousePointerTracker.shared.currentSample
            return
        }

        let sample = MousePointerTracker.shared.currentSample
        defer { lastEdgeTrapSample = sample }
        let previous = lastEdgeTrapSample
        guard sample.timestamp >= edgeTrapSuppressedUntil,
              let layoutMonitor = sortedMonitors.first(where: { workspaceSidebarMonitorScopeId(for: $0) == monitorScopeId }),
              hasMonitorImmediatelyLeft(of: layoutMonitor),
              crossesLeftEdgeTrapRegion(point: sample.point, previous: previous?.point, of: layoutMonitor)
        else {
            edgeTrapStartedAt = nil
            return
        }

        let deltaX = previous.map { sample.point.x - $0.point.x } ?? 0
        let isLeftwardFlick = deltaX <= -edgeTrapReleaseVelocityThreshold
        let isContinuingTrap = edgeTrapStartedAt != nil && sample.point.x <= layoutMonitor.rect.minX + edgeTrapBandWidth
        let shouldTrap = isContinuingTrap || isLeftwardFlick || isMouseWindowDragInProgress()
        guard shouldTrap else {
            edgeTrapStartedAt = nil
            return
        }

        let startedAt = edgeTrapStartedAt ?? sample.timestamp
        edgeTrapStartedAt = startedAt
        guard sample.timestamp - startedAt < edgeTrapReleaseDelay else {
            edgeTrapStartedAt = nil
            edgeTrapSuppressedUntil = sample.timestamp + edgeTrapCrossingGrace
            return
        }

        let trappedPoint = CGPoint(
            x: layoutMonitor.rect.minX + 1,
            y: sample.point.y.coerce(in: layoutMonitor.rect.minY ... max(layoutMonitor.rect.minY, layoutMonitor.rect.maxY - 1))
        )
        CGWarpMouseCursorPosition(trappedPoint)
        MousePointerTracker.shared.note(point: trappedPoint, timestamp: sample.timestamp)
    }

    private func hasMonitorImmediatelyLeft(of monitor: Monitor) -> Bool {
        sortedMonitors.contains { other in
            other.rect.maxX == monitor.rect.minX &&
                other.rect.maxY > monitor.rect.minY &&
                other.rect.minY < monitor.rect.maxY
        }
    }

    private func isInsideVerticalSpan(_ point: CGPoint, of monitor: Monitor) -> Bool {
        point.y >= monitor.rect.minY && point.y < monitor.rect.maxY
    }

    private func crossesLeftEdgeTrapRegion(point: CGPoint, previous: CGPoint?, of monitor: Monitor) -> Bool {
        if isInsideVerticalSpan(point, of: monitor),
           point.x >= monitor.rect.minX - edgeTrapBandWidth,
           point.x <= monitor.rect.minX + edgeTrapBandWidth
        {
            return true
        }
        guard let previous else { return false }
        let crossedLeftEdge = previous.x >= monitor.rect.minX && point.x < monitor.rect.minX
        let crossedBackIntoMonitor = previous.x < monitor.rect.minX && point.x >= monitor.rect.minX
        let crossedTrapBand = previous.x > monitor.rect.minX + edgeTrapBandWidth &&
            point.x < monitor.rect.minX - edgeTrapBandWidth
        guard crossedLeftEdge || crossedBackIntoMonitor || crossedTrapBand else { return false }
        return segmentIntersectsVerticalSpan(from: previous, to: point, of: monitor)
    }

    private func segmentIntersectsVerticalSpan(from start: CGPoint, to end: CGPoint, of monitor: Monitor) -> Bool {
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)
        return maxY >= monitor.rect.minY && minY < monitor.rect.maxY
    }
}
