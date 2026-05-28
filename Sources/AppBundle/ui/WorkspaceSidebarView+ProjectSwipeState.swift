import AppKit
import SwiftUI

extension WorkspaceSidebarView {
    var selectedProjectIndex: Int? {
        let projectId = browsedProjectId ?? snapshot.activeProjectId
        return snapshot.projects.firstIndex { $0.id == projectId }
            ?? snapshot.projects.indices.first
    }

    var projectPagerDisplayIndex: Int? {
        if let projectSwipeStartProjectId,
           let index = snapshot.projects.firstIndex(where: { $0.id == projectSwipeStartProjectId }) {
            return index
        }
        return selectedProjectIndex
    }

    func resetProjectSwipe() {
        projectSwipeTranslation = 0
        projectSwipeStartProjectId = nil
        projectSwipeDidCrossBreakPoint = false
    }

    func resetProjectSwipeWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            resetProjectSwipe()
        }
    }

    func resetTransientSidebarState() {
        browseMode = .activeProject
        showsPinnedActiveWorkspaceForBrowsedProject = true
        activeInUseOverrideWorkspaceName = nil
        isProjectMenuOpen = false
        isSidebarCollapsing = false
        isSidebarExpanding = false
        finishWorkspaceRename(cancelled: true)
        resetProjectEdgeDrag()
        resetProjectSwipeWithoutAnimation()
    }

    func performWorkspaceSidebarProjectHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    func handleProjectEdgeDrag(pointer: CGPoint, expansionProgress: CGFloat) {
        guard expansionProgress >= 0.95,
              snapshot.projects.count > 1,
              let panel = WorkspaceSidebarPanel.panel(containing: pointer),
              panel.monitorScopeId == snapshot.targetMonitorScopeId,
              let frame = panel.visibleScreenRectNormalized()
        else {
            resetProjectEdgeDrag()
            return
        }
        guard let direction = projectEdgeDragDirection(pointer: pointer, panelFrame: frame) else {
            lastProjectEdgeDragDirection = nil
            return
        }
        guard let currentIndex = selectedProjectIndex,
              let nextIndex = workspaceSidebarProjectIndexAfterSwipe(
                currentIndex: currentIndex,
                projectCount: snapshot.projects.count,
                direction: direction
              )
        else {
            lastProjectEdgeDragDirection = direction
            return
        }

        let now = Date()
        guard lastProjectEdgeDragDirection != direction ||
              now.timeIntervalSince(lastProjectEdgeDragSwitchAt) >= workspaceSidebarProjectEdgeDragRepeatDelay
        else {
            return
        }
        lastProjectEdgeDragDirection = direction
        lastProjectEdgeDragSwitchAt = now
            performWorkspaceSidebarProjectHaptic(.alignment)
        withAnimation(.easeOut(duration: 0.12)) {
            browseMode = .split(otherProjectId: snapshot.projects[nextIndex].id)
            showsPinnedActiveWorkspaceForBrowsedProject = false
            resetProjectSwipe()
        }
    }

    func resetProjectEdgeDrag() {
        lastProjectEdgeDragDirection = nil
        lastProjectEdgeDragSwitchAt = .distantPast
    }

    private func projectEdgeDragDirection(pointer: CGPoint, panelFrame: Rect) -> Int? {
        if pointer.x <= panelFrame.minX + workspaceSidebarProjectEdgeDragBandWidth {
            return -1
        }
        if pointer.x >= panelFrame.maxX - workspaceSidebarProjectEdgeDragBandWidth {
            return 1
        }
        return nil
    }
}

private let workspaceSidebarProjectEdgeDragBandWidth: CGFloat = 36
private let workspaceSidebarProjectEdgeDragRepeatDelay: TimeInterval = 0.45
