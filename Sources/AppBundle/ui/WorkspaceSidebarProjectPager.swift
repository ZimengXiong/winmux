import AppKit
import Common
import SwiftUI

struct WorkspaceSidebarProjectPager: View {
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId
    let expansionProgress: CGFloat
    let layout: WorkspaceSidebarConfiguration
    @Binding var isProjectMenuOpen: Bool
    @Binding var renamingProjectId: WorkspaceProjectId?
    @Binding var renamingProjectText: String
    let onSelectProject: (WorkspaceProjectId) -> Void
    let onCreateProject: () -> Void
    let onBeginRenameProject: (WorkspaceSidebarProjectViewModel) -> Void
    let onCommitRenameProject: @MainActor @Sendable () -> Void
    let onCancelRenameProject: @MainActor @Sendable () -> Void
    let onSetProjectColor: (WorkspaceSidebarProjectViewModel, String?) -> Void
    let onDeleteProject: (WorkspaceSidebarProjectViewModel) -> Void

    @State var isHovered = false
    @State var pressedProjectId: WorkspaceProjectId? = nil
    @State var hoveredProjectDotId: WorkspaceProjectId? = nil
    @State var projectTrackScrollTargetId: WorkspaceProjectId? = nil
    @State var projectTrackContentMinX: CGFloat = 0
    @State var projectTrackContentWidth: CGFloat = 0
    @State var projectTrackViewportWidth: CGFloat = 0

    var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress, layout: layout) }
    var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    var currentIndex: Int? {
        projects.firstIndex { $0.id == selectedProjectId }
            ?? projects.indices.first
    }
    var selectedProject: WorkspaceSidebarProjectViewModel? {
        if let renamingProjectId,
           let renamingProject = projects.first(where: { $0.id == renamingProjectId })
        {
            return renamingProject
        }
        return projects.first { $0.id == selectedProjectId }
            ?? projects.first
    }
    var expandedProjectControlsHeight: CGFloat {
        (workspaceSidebarPagerHeight * 2) + 4
    }
    var pagerHeight: CGFloat {
        let controlsHeight = isCompact ? workspaceSidebarPagerHeight : expandedProjectControlsHeight
        guard isProjectMenuOpen && !isCompact else {
            return controlsHeight
        }
        let rowCount = CGFloat(projects.count + 1)
        let popupPadding = (workspaceSidebarMenuRowSpacing + 1) * 2
        let rowSpacing = CGFloat(max(projects.count - 1, 0)) * workspaceSidebarMenuRowSpacing
        let dividerHeight = 0.5 + (workspaceSidebarMenuRowSpacing * 2)
        let popupHeight = (rowCount * workspaceSidebarDropdownHeight) + rowSpacing + dividerHeight + popupPadding
        return popupHeight + workspaceSidebarSectionGap + controlsHeight
    }
    var footerSpacing: CGFloat { isCompact ? 2 : 8 }
    var projectCreateButtonWidth: CGFloat { workspaceSidebarDropdownHeight }
    var projectPopupWidth: CGFloat {
        let names = projects.map(\.displayName) + ["Project"]
        let maxTextWidth = names.map {
            ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width
        }.max() ?? 0
        return max(ceil(maxTextWidth) + 50, projectMenuWidth)
    }
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
        return max(sectionWidth, 24)
    }
    var compactProjectControlsHeight: CGFloat {
        let contentHeight = CGFloat(projects.count) * workspaceSidebarProjectDotFrameHeight
        let maxVisibleHeight = workspaceSidebarProjectDotFrameHeight * 5
        return min(max(contentHeight, workspaceSidebarPagerHeight), maxVisibleHeight)
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
        .contextMenu {
            Button("New Project") {
                onCreateProject()
            }
        }
        .transaction { $0.animation = nil }
    }
}
