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
                if let pinnedActiveWorkspace = pinnedActiveWorkspace(
                    displayedProjectId: projectId,
                    pageWorkspaces: workspaces
                ) {
                    workspaceSection(
                        workspace: pinnedActiveWorkspace,
                        expansionProgress: expansionProgress,
                        emitsDropTarget: true,
                        allowsWorkspaceActivation: false,
                        isPinnedActiveWorkspace: true,
                        projectContextLabel: projectName(snapshot.activeProjectId),
                        projectContextColor: projectColor(snapshot.activeProjectId)
                    )
                }
                ForEach(workspaces) { workspace in
                    workspaceSection(
                        workspace: workspace,
                        expansionProgress: expansionProgress,
                        emitsDropTarget: true,
                        allowsWorkspaceActivation: allowsWorkspaceActivation(projectId: projectId),
                        isPinnedActiveWorkspace: false,
                        projectContextLabel: browsedProjectId != nil && projectId != snapshot.selectedProjectId ? projectName(projectId) : nil,
                        projectContextColor: browsedProjectId != nil && projectId != snapshot.selectedProjectId ? projectColor(projectId) : nil
                    )
                }
                if workspaceSidebarShowsCreateWorkspace(selectedScopeId: snapshot.selectedMonitorScopeId) && browsedProjectId == nil {
                    WorkspaceSidebarCreateWorkspaceSection(
                        dragPreview: snapshot.dropPreview,
                        expansionProgress: expansionProgress,
                        layout: snapshot.configuration,
                        emitsDropTarget: true,
                        onCreateWorkspace: {
                            actions.send(.createWorkspace(
                                projectId: projectId,
                                monitorScopeId: workspaceSidebarWorkspaceCreateScope(
                                    selectedScopeId: snapshot.selectedMonitorScopeId,
                                    targetMonitorScopeId: snapshot.targetMonitorScopeId,
                                    focusedScopeId: snapshot.focusedMonitorScopeId,
                                )
                            ))
                        },
                        onDropPayload: { payload in
                            let monitorScopeId = workspaceSidebarWorkspaceCreateScope(
                                selectedScopeId: snapshot.selectedMonitorScopeId,
                                targetMonitorScopeId: snapshot.targetMonitorScopeId,
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
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.top, topPadding)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func workspaceSection(
        workspace: WorkspaceSidebarWorkspaceViewModel,
        expansionProgress: CGFloat,
        emitsDropTarget: Bool,
        allowsWorkspaceActivation: Bool,
        isPinnedActiveWorkspace: Bool,
        projectContextLabel: String? = nil,
        projectContextColor: Color? = nil
    ) -> some View {
        let isFromOtherDisplay = snapshot.selectedMonitorScopeId == workspaceSidebarAllScopeId &&
            workspace.monitorScopeId != snapshot.targetMonitorScopeId &&
            workspace.monitorScopeId != workspaceSidebarAllScopeId
        let isInUseOnOtherDisplay = allowsWorkspaceActivation &&
            !isPinnedActiveWorkspace &&
            workspaceSidebarWorkspaceIsInUseOnOtherDisplay(
                workspace,
                selectedScopeId: snapshot.targetMonitorScopeId
            )
        WorkspaceSidebarWorkspaceSection(
            workspace: workspace,
            dragPreview: snapshot.dropPreview,
            expansionProgress: expansionProgress,
            layout: snapshot.configuration,
            emitsDropTarget: emitsDropTarget,
            isFromOtherDisplay: isFromOtherDisplay,
            isInUseOnOtherDisplay: isInUseOnOtherDisplay,
            allowsWorkspaceActivation: allowsWorkspaceActivation,
            isPinnedActiveWorkspace: isPinnedActiveWorkspace,
            isActiveOnTargetMonitor: workspace.monitorScopeId == snapshot.targetMonitorScopeId && workspace.isVisible,
            projectContextLabel: projectContextLabel,
            projectContextColor: projectContextColor,
            activeInUseOverrideWorkspaceName: $activeInUseOverrideWorkspaceName,
            actions: actions,
        )
    }

    private func allowsWorkspaceActivation(projectId: WorkspaceProjectId) -> Bool {
        snapshot.selectedMonitorScopeId == workspaceSidebarDefaultScopeId &&
            browsedProjectId == nil &&
            projectId == snapshot.activeProjectId
    }

    private func projectColorHex(_ projectId: WorkspaceProjectId) -> String? {
        snapshot.projects.first { $0.id == projectId }?.colorHex
    }

    private func projectName(_ projectId: WorkspaceProjectId) -> String {
        snapshot.projects.first { $0.id == projectId }?.displayName ?? "Project"
    }

    private func projectColor(_ projectId: WorkspaceProjectId) -> Color {
        workspaceSidebarProjectColor(projectId: projectId, configuredHex: projectColorHex(projectId))
    }

    private func pinnedActiveWorkspace(
        displayedProjectId: WorkspaceProjectId,
        pageWorkspaces: [WorkspaceSidebarWorkspaceViewModel]
    ) -> WorkspaceSidebarWorkspaceViewModel? {
        guard browsedProjectId != nil,
              displayedProjectId != snapshot.activeProjectId,
              !pageWorkspaces.contains(where: { workspaceIsActiveOnTargetMonitor($0) }),
              let focusedWorkspace = snapshot.workspaces.first(where: { workspaceIsActiveOnTargetMonitor($0) }),
              workspaceSidebarWorkspaceMatchesScope(
                focusedWorkspace,
                selectedScopeId: snapshot.selectedMonitorScopeId,
                focusedMonitorScopeId: snapshot.focusedMonitorScopeId
              )
        else {
            return nil
        }
        return focusedWorkspace
    }

    private func workspaceIsActiveOnTargetMonitor(_ workspace: WorkspaceSidebarWorkspaceViewModel) -> Bool {
        workspace.isVisible && workspace.monitorScopeId == snapshot.targetMonitorScopeId
    }
}
