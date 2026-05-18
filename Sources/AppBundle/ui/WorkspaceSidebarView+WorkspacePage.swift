import Common
import SwiftUI

extension WorkspaceSidebarView {
    @ViewBuilder
    func projectPageSlot(
        index: Int,
        project: WorkspaceSidebarProjectViewModel,
        displayIndex: Int,
        pageWidth: CGFloat,
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        visibleWorkspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
        swipeDirection: Int?,
    ) -> some View {
        if shouldRenderWorkspaceSidebarProjectPage(
            index: index,
            displayIndex: displayIndex,
            swipeDirection: swipeDirection,
            projectCount: snapshot.projects.count,
        ) {
            workspacePage(
                projectId: project.id,
                workspaces: visibleWorkspacesByProject[project.id] ?? [],
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                isInteractive: index == displayIndex,
            )
            .frame(width: pageWidth, alignment: .topLeading)
            .allowsHitTesting(index == displayIndex)
        } else {
            Color.clear
                .frame(width: pageWidth, alignment: .topLeading)
                .allowsHitTesting(false)
        }
    }

    func workspacePage(
        projectId: WorkspaceProjectId,
        workspaces: [WorkspaceSidebarWorkspaceViewModel],
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        isInteractive: Bool,
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(workspaces) { workspace in
                    let isFromOtherDisplay = snapshot.selectedMonitorScopeId == workspaceSidebarAllScopeId &&
                        workspace.monitorScopeId != snapshot.focusedMonitorScopeId &&
                        workspace.monitorScopeId != workspaceSidebarAllScopeId
                    let isInUseOnOtherDisplay = workspaceSidebarWorkspaceIsInUseOnOtherDisplay(
                        workspace,
                        selectedScopeId: snapshot.selectedMonitorScopeId
                    )
                    WorkspaceSidebarWorkspaceSection(
                        workspace: workspace,
                        dragPreview: snapshot.dropPreview,
                        expansionProgress: expansionProgress,
                        emitsDropTarget: isInteractive,
                        isFromOtherDisplay: isFromOtherDisplay,
                        isInUseOnOtherDisplay: isInUseOnOtherDisplay,
                        activeInUseOverrideWorkspaceName: $activeInUseOverrideWorkspaceName,
                        actions: actions,
                    )
                }
                WorkspaceSidebarCreateWorkspaceSection(
                    dragPreview: snapshot.dropPreview,
                    expansionProgress: expansionProgress,
                    emitsDropTarget: isInteractive,
                    onCreateWorkspace: {
                        actions.send(.createWorkspace(
                            projectId: projectId,
                            monitorScopeId: workspaceSidebarWorkspaceCreateScope(
                                selectedScopeId: snapshot.selectedMonitorScopeId,
                                focusedScopeId: snapshot.focusedMonitorScopeId,
                            )
                        ))
                    },
                    onDropPayload: { payload in
                        let monitorScopeId = workspaceSidebarWorkspaceCreateScope(
                            selectedScopeId: snapshot.selectedMonitorScopeId,
                            focusedScopeId: snapshot.focusedMonitorScopeId,
                        )
                        switch payload {
                            case .window(let windowId):
                                actions.send(.moveWindowToNewWorkspace(
                                    windowId,
                                    projectId: projectId,
                                    monitorScopeId: monitorScopeId,
                                ))
                            case .tabGroup(let representativeWindowId):
                                actions.send(.moveTabGroupToNewWorkspace(
                                    representativeWindowId,
                                    projectId: projectId,
                                    monitorScopeId: monitorScopeId,
                                ))
                        }
                    },
                    actions: actions,
                )
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.top, topPadding)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
