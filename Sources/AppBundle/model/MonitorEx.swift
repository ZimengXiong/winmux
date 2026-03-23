import AppKit

extension Monitor {
    @MainActor
    var workspaceSidebarInset: CGFloat {
        let sidebar = config.workspaceSidebar
        guard sidebar.enabled,
              let resolvedMonitor = sidebar.resolvedMonitor(sortedMonitors: sortedMonitors),
              resolvedMonitor.rect.topLeftCorner == rect.topLeftCorner
        else { return 0 }
        return CGFloat(sidebar.collapsedWidth)
    }

    @MainActor
    var visibleRectPaddedByOuterGaps: Rect {
        let topLeft = visibleRect.topLeftCorner
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: self)
        let leftInset = gaps.outer.left.toDouble() + workspaceSidebarInset
        return Rect(
            topLeftX: topLeft.x + leftInset,
            topLeftY: topLeft.y + gaps.outer.top.toDouble(),
            width: visibleRect.width - leftInset - gaps.outer.right.toDouble(),
            height: visibleRect.height - gaps.outer.top.toDouble() - gaps.outer.bottom.toDouble(),
        )
    }

    var monitorId_oneBased: Int? {
        let sorted = sortedMonitors
        let origin = self.rect.topLeftCorner
        return sorted.firstIndex { $0.rect.topLeftCorner == origin }.map { $0 + 1 }
    }
}
