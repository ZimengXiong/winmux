import AppKit

extension WorkspaceSidebarPanel {
    static func suppressEdgeTrapForWorkspaceActivation(duration: TimeInterval = 0.75) {
        let until = ProcessInfo.processInfo.systemUptime + duration
        for panel in visiblePanels {
            debugWorkspaceSidebarEdgeTrapLog("suppress panel=\(panel.monitorScopeId) until=\(until) sample=\(MousePointerTracker.shared.currentSample)")
            panel.edgeTrapStartedAt = nil
            panel.edgeTrapSuppressedUntil = max(panel.edgeTrapSuppressedUntil, until)
            panel.lastEdgeTrapSample = MousePointerTracker.shared.currentSample
        }
    }

    static func trapCursorForVisiblePanelsIfNeeded() {
        for panel in visiblePanels {
            panel.trapCursorForLeftEdgeSidebarActivationIfNeeded()
        }
    }

    func trapCursorForLeftEdgeSidebarActivationIfNeeded() {
        let sample = MousePointerTracker.shared.currentSample
        let collapsedWidth = CGFloat(config.workspaceSidebar.collapsedWidth)
        debugWorkspaceSidebarEdgeTrapLog(
            "entry panel=\(monitorScopeId) visible=\(isVisible) enabled=\(config.workspaceSidebar.enabled) shift=\(currentSessionModifierFlags().contains(.maskShift)) mouseDrag=\(isMouseWindowDragInProgress()) sidebarDrag=\(isWorkspaceSidebarItemDragActive()) width=\(viewModel.workspaceSidebarVisibleWidth) collapsed=\(collapsedWidth) sample=\(sample) previous=\(String(describing: lastEdgeTrapSample)) suppressUntil=\(edgeTrapSuppressedUntil) startedAt=\(String(describing: edgeTrapStartedAt))"
        )
        guard isVisible,
              config.workspaceSidebar.enabled,
              !currentSessionModifierFlags().contains(.maskShift),
              !isMouseWindowDragInProgress(),
              !isWorkspaceSidebarItemDragActive(),
              viewModel.workspaceSidebarVisibleWidth <= collapsedWidth + 0.5
        else {
            debugWorkspaceSidebarEdgeTrapLog("skipPreconditions panel=\(monitorScopeId)")
            edgeTrapStartedAt = nil
            lastEdgeTrapSample = sample
            return
        }

        defer { lastEdgeTrapSample = sample }
        let previous = lastEdgeTrapSample
        guard sample.timestamp >= edgeTrapSuppressedUntil,
              let layoutMonitor = sortedMonitors.first(where: { workspaceSidebarMonitorScopeId(for: $0) == monitorScopeId })
        else {
            debugWorkspaceSidebarEdgeTrapLog("skipSuppressedOrNoMonitor panel=\(monitorScopeId) sampleTime=\(sample.timestamp) suppressUntil=\(edgeTrapSuppressedUntil)")
            edgeTrapStartedAt = nil
            return
        }
        let hasLeftMonitor = hasMonitorImmediatelyLeft(of: layoutMonitor)
        let crossesTrapRegion = crossesLeftEdgeTrapRegion(point: sample.point, previous: previous?.point, of: layoutMonitor)
        guard hasLeftMonitor, crossesTrapRegion else {
            debugWorkspaceSidebarEdgeTrapLog("skipRegion panel=\(monitorScopeId) hasLeftMonitor=\(hasLeftMonitor) crosses=\(crossesTrapRegion) monitorFrame=\(layoutMonitor.rect) samplePoint=\(sample.point) previousPoint=\(String(describing: previous?.point))")
            edgeTrapStartedAt = nil
            return
        }

        let deltaX = previous.map { sample.point.x - $0.point.x } ?? 0
        let isLeftwardFlick = deltaX <= -edgeTrapReleaseVelocityThreshold
        let isContinuingTrap = edgeTrapStartedAt != nil && sample.point.x <= layoutMonitor.rect.minX + edgeTrapBandWidth
        let shouldTrap = isContinuingTrap || isLeftwardFlick || isMouseWindowDragInProgress()
        guard shouldTrap else {
            debugWorkspaceSidebarEdgeTrapLog("skipVelocity panel=\(monitorScopeId) deltaX=\(deltaX) isLeftwardFlick=\(isLeftwardFlick) isContinuingTrap=\(isContinuingTrap)")
            edgeTrapStartedAt = nil
            return
        }

        let startedAt = edgeTrapStartedAt ?? sample.timestamp
        edgeTrapStartedAt = startedAt
        guard sample.timestamp - startedAt < edgeTrapReleaseDelay else {
            debugWorkspaceSidebarEdgeTrapLog("release panel=\(monitorScopeId) elapsed=\(sample.timestamp - startedAt) grace=\(edgeTrapCrossingGrace)")
            edgeTrapStartedAt = nil
            edgeTrapSuppressedUntil = sample.timestamp + edgeTrapCrossingGrace
            return
        }

        let trappedPoint = CGPoint(
            x: layoutMonitor.rect.minX + 1,
            y: sample.point.y.coerce(in: layoutMonitor.rect.minY ... max(layoutMonitor.rect.minY, layoutMonitor.rect.maxY - 1))
        )
        debugWorkspaceSidebarEdgeTrapLog("warp panel=\(monitorScopeId) from=\(sample.point) to=\(trappedPoint) deltaX=\(deltaX) isLeftwardFlick=\(isLeftwardFlick) isContinuingTrap=\(isContinuingTrap) elapsed=\(sample.timestamp - startedAt) monitorFrame=\(layoutMonitor.rect)")
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
