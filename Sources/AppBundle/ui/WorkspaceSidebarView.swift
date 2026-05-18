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
            }
        }
        .onChange(of: snapshot.selectedProjectId) { _ in
            browsedProjectId = nil
            activeInUseOverrideWorkspaceName = nil
            isProjectMenuOpen = false
            resetProjectSwipeWithoutAnimation()
        }
        .onChange(of: snapshot.projects) { _ in
            if let browsedProjectId, !snapshot.projects.contains(where: { $0.id == browsedProjectId }) {
                self.browsedProjectId = nil
            }
            isProjectMenuOpen = false
            resetProjectSwipeWithoutAnimation()
        }
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
