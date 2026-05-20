import SwiftUI

extension WorkspaceSidebarPanel {
    func showHoverCue(cueWidth: CGFloat, expandedWidth: CGFloat, collapsedWidth: CGFloat) {
        if !isVisible {
            refresh()
        }
        if viewModel.workspaceSidebarVisibleWidth < cueWidth {
            animateVisibleSidebarWidth(
                cueWidth,
                animation: .spring(response: hoverCueAnimationResponse, dampingFraction: 0.72),
            )
        } else {
            updateMousePassthrough()
        }

        guard isMouseDeepEnoughToExpand(collapsedWidth: collapsedWidth) else {
            pendingExpand?.cancel()
            pendingExpand = nil
            return
        }
        scheduleHoverExpansion(expandedWidth: expandedWidth, collapsedWidth: collapsedWidth)
    }

    func scheduleHoverExpansion(expandedWidth: CGFloat, collapsedWidth: CGFloat) {
        guard pendingExpand == nil else { return }
        let expand = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingExpand = nil
            guard self.isMouseInsideHoverRegion(),
                  self.isMouseDeepEnoughToExpand(collapsedWidth: collapsedWidth)
            else { return }
            self.expandSidebar(to: expandedWidth)
        }
        pendingExpand = expand
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverOpenDelay, execute: expand)
    }
}
