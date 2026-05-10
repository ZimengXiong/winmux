import AppKit

extension Monitor {
    @MainActor
    var workspaceSidebarInset: CGFloat {
        guard config.workspaceSidebar.enabled else { return 0 }
        return workspaceSidebarResolvedPanelMonitor().rect.topLeftCorner == rect.topLeftCorner
            ? CGFloat(config.workspaceSidebar.collapsedWidth)
            : 0
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

    @MainActor
    var monitorId_oneBased: Int? {
        sortedMonitors.firstIndex { $0.rect.topLeftCorner == rect.topLeftCorner }.map { $0 + 1 }
    }
}
