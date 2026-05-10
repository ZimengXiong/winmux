import AppKit
import Common
import SwiftUI

struct WorkspaceSidebarProjectPager: View {
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId
    let expansionProgress: CGFloat
    let swipeDirection: Int?
    let switchProgress: CGFloat
    let edgeProgress: CGFloat

    @State var isHovered = false
    @State var pressedProjectId: WorkspaceProjectId? = nil
    @State var editingProjectId: WorkspaceProjectId? = nil
    @State var editingProjectDraft = ""

    var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress) }
    var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    var currentIndex: Int? {
        projects.firstIndex { $0.id == selectedProjectId }
            ?? projects.indices.first
    }
    var selectedProject: WorkspaceSidebarProjectViewModel? {
        projects.first { $0.id == selectedProjectId }
            ?? projects.first
    }
    var swipeTargetIndex: Int? {
        guard let swipeDirection else { return nil }
        return workspaceSidebarProjectIndexAfterSwipe(
            currentIndex: currentIndex,
            projectCount: projects.count,
            direction: swipeDirection,
        )
    }
    var footerSpacing: CGFloat { isCompact ? 2 : 8 }
    var projectMenuWidth: CGFloat {
        let selectedProjectName = selectedProject?.displayName ?? "Project"
        let textWidth = (selectedProjectName as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .medium)],
        ).width
        return min(max(ceil(textWidth) + 46, 92), 136)
    }
    var projectTrackWidth: CGFloat {
        if isCompact {
            return max(sectionWidth - 4, 12)
        }
        return max(sectionWidth - projectMenuWidth - footerSpacing, 24)
    }

    var body: some View {
        if !projects.isEmpty {
            pagerContent
                .frame(width: sectionWidth, height: workspaceSidebarPagerHeight, alignment: .center)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("New") {
                        createWorkspaceSidebarProject()
                    }
                }
                .onHover { hovering in
                    isHovered = hovering
                }
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: isHovered)
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: currentIndex)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.88), value: edgeProgress)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
        }
    }

    var pagerContent: some View {
        Group {
            if isCompact {
                compactProjectIndicator
            } else {
                HStack(alignment: .center, spacing: footerSpacing) {
                    projectDotTrack
                    projectMenu
                        .frame(width: projectMenuWidth, height: workspaceSidebarPagerHeight, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, isCompact ? 2 : 0)
        .frame(width: sectionWidth, height: workspaceSidebarPagerHeight, alignment: .center)
    }
}
