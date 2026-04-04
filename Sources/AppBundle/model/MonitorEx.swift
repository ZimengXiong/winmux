import AppKit

extension Monitor {
    @MainActor
    var workspaceSidebarInset: CGFloat {
        config.workspaceSidebar.enabled ? CGFloat(config.workspaceSidebar.collapsedWidth) : 0
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
        1
    }
}
