import AppKit
import Common
import SwiftUI

struct WorkspaceSidebarProjectPager: View {
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId
    let expansionProgress: CGFloat
    let layout: WorkspaceSidebarLayoutSnapshot
    @Binding var isProjectMenuOpen: Bool
    let onSelectProject: (WorkspaceProjectId) -> Void
    let onCreateProject: () -> Void
    let onRenameProject: (WorkspaceSidebarProjectViewModel, String) -> Void
    let onSetProjectColor: (WorkspaceSidebarProjectViewModel, String?) -> Void
    let onDeleteProject: (WorkspaceSidebarProjectViewModel) -> Void

    @State var isHovered = false
    @State var pressedProjectId: WorkspaceProjectId? = nil
    @State var editingProjectId: WorkspaceProjectId? = nil
    @State var editingProjectDraft = ""

    var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress, layout: layout) }
    var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    var currentIndex: Int? {
        projects.firstIndex { $0.id == selectedProjectId }
            ?? projects.indices.first
    }
    var selectedProject: WorkspaceSidebarProjectViewModel? {
        projects.first { $0.id == selectedProjectId }
            ?? projects.first
    }
    var pagerHeight: CGFloat {
        guard isProjectMenuOpen && !isCompact else {
            return workspaceSidebarPagerHeight
        }
        let rowCount = CGFloat(projects.count + 1)
        let popupPadding = (workspaceSidebarMenuRowSpacing + 1) * 2
        let rowSpacing = CGFloat(max(projects.count - 1, 0)) * workspaceSidebarMenuRowSpacing
        let dividerHeight = 0.5 + (workspaceSidebarMenuRowSpacing * 2)
        let popupHeight = (rowCount * workspaceSidebarMenuRowHeight) + rowSpacing + dividerHeight + popupPadding
        return popupHeight + workspaceSidebarSectionGap + workspaceSidebarPagerHeight
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
                .frame(width: sectionWidth, height: pagerHeight, alignment: .bottom)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovered = hovering
                }
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: isHovered)
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: currentIndex)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                .zIndex(isProjectMenuOpen ? 20 : 0)
        }
    }

    var pagerContent: some View {
        Group {
            if isCompact {
                compactProjectIndicator
            } else {
                ZStack(alignment: .bottomTrailing) {
                    projectControls
                    projectPopup
                }
                .frame(width: sectionWidth, height: pagerHeight, alignment: .bottomTrailing)
                .transaction { $0.animation = nil }
            }
        }
        .padding(.horizontal, isCompact ? 2 : 0)
        .frame(width: sectionWidth, height: pagerHeight, alignment: .bottom)
        .transaction { $0.animation = nil }
    }
}
