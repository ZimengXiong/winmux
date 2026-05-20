import AppKit
import Common
import SwiftUI

struct WorkspaceSidebarView: View {
    let snapshot: WorkspaceSidebarSnapshot
    let actions: WorkspaceSidebarActions
    @State var projectSwipeTranslation: CGFloat = 0
    @State var projectSwipeStartProjectId: WorkspaceProjectId? = nil
    @State var projectSwipeDidCrossBreakPoint = false
    @State var projectPagerWidth: CGFloat = 0
    @State var browsedProjectId: WorkspaceProjectId? = nil
    @State var activeInUseOverrideWorkspaceName: String? = nil
    @State var isProjectMenuOpen = false
    @State var isSidebarCollapsing = false
    @State var isSidebarExpanding = false
    @State var renamingProjectId: WorkspaceProjectId? = nil
    @State var renamingProjectText = ""

    init(snapshot: WorkspaceSidebarSnapshot, actions: WorkspaceSidebarActions = WorkspaceSidebarActions()) {
        self.snapshot = snapshot
        self.actions = actions
    }

    var body: some View {
        let collapsedWidth = snapshot.configuration.collapsedWidth
        let expandedWidth = snapshot.configuration.expandedWidth
        let expansionProgress = max(
            0,
            min(1, (snapshot.visibleWidth - collapsedWidth) / max(expandedWidth - collapsedWidth, 1)),
        )
        
        ZStack(alignment: .leading) {
            sidebarContent(expansionProgress: expansionProgress)
                .frame(width: max(snapshot.visibleWidth, 0), alignment: .leading)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: max(snapshot.visibleWidth, 0))
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.clear)
        .onChange(of: snapshot.visibleWidth) { visibleWidth in
            if visibleWidth <= collapsedWidth + 0.5 {
                resetTransientSidebarState()
            } else if visibleWidth >= collapsedWidth + 8 {
                isSidebarCollapsing = false
            }
            if visibleWidth >= expandedWidth - 0.5 {
                isSidebarExpanding = false
            }
        }
        .onChange(of: snapshot.selectedProjectId) { _ in
            browsedProjectId = nil
            activeInUseOverrideWorkspaceName = nil
            finishProjectRename(cancelled: true)
            resetProjectSwipeWithoutAnimation()
        }
        .onChange(of: snapshot.projects) { _ in
            if let browsedProjectId, !snapshot.projects.contains(where: { $0.id == browsedProjectId }) {
                self.browsedProjectId = nil
            }
            if let renamingProjectId, !snapshot.projects.contains(where: { $0.id == renamingProjectId }) {
                finishProjectRename(cancelled: true)
            }
            isProjectMenuOpen = false
            resetProjectSwipeWithoutAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarWillCollapseNotification)) { _ in
            guard snapshot.visibleWidth > collapsedWidth + 0.5 else {
                isSidebarCollapsing = false
                return
            }
            withAnimation(.easeOut(duration: 0.08)) {
                isProjectMenuOpen = false
                isSidebarCollapsing = true
                isSidebarExpanding = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarWillExpandNotification)) { _ in
            guard snapshot.visibleWidth > collapsedWidth + 0.5 else {
                isSidebarExpanding = false
                return
            }
            isSidebarCollapsing = false
            isSidebarExpanding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarDismissProjectMenusNotification)) { _ in
            if isProjectMenuOpen {
                withAnimation(.easeOut(duration: 0.10)) {
                    isProjectMenuOpen = false
                }
            }
        }
    }

    func beginProjectRename(_ project: WorkspaceSidebarProjectViewModel) {
        debugWorkspaceSidebarRenameLog("beginProjectRename project=\(project.id.rawValue) displayName=\(project.displayName) selected=\(snapshot.selectedProjectId.rawValue) visibleWidth=\(snapshot.visibleWidth)")
        if project.id != snapshot.selectedProjectId {
            browsedProjectId = project.id
        }
        renamingProjectId = project.id
        renamingProjectText = project.displayName
        isProjectMenuOpen = false
        WorkspaceSidebarPanel.shared.prepareForInlineTextEditing()
    }

    func finishProjectRename(cancelled: Bool = false) {
        guard let projectId = renamingProjectId else { return }
        let displayName = renamingProjectText.trimmingCharacters(in: .whitespacesAndNewlines)
        debugWorkspaceSidebarRenameLog("finishProjectRename project=\(projectId.rawValue) cancelled=\(cancelled) raw=\(renamingProjectText) trimmed=\(displayName)")
        renamingProjectId = nil
        renamingProjectText = ""
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
        guard !cancelled, !displayName.isEmpty else { return }
        actions.send(.renameProject(projectId, displayName: displayName))
    }
}

struct WorkspaceSidebarContainerView: View {
    @ObservedObject var viewModel: TrayMenuModel
    let actions: WorkspaceSidebarActions

    var body: some View {
        WorkspaceSidebarView(
            snapshot: workspaceSidebarSnapshot(from: viewModel),
            actions: actions
        )
    }
}
