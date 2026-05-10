import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarView {
    func sidebarContent(expansionProgress: CGFloat) -> some View {
        let isCompact = expansionProgress < workspaceSidebarRowsRevealProgress
        let leadingInset = workspaceSidebarOuterLeadingPadding(isCompact: isCompact)
        let trailingInset = workspaceSidebarOuterTrailingPadding(isCompact: isCompact)
        let showsMonitorSelector = !isCompact && viewModel.workspaceSidebarShowsMonitorSelector
        let projectSwipeDirection = workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: projectSwipeTranslation,
            verticalTranslation: 0,
            minimumDistance: 1,
        )
        let activeProjectIndex = projectPagerDisplayIndex
        let projectSwipeProgress = workspaceSidebarProjectEdgeCreationProgress(
            currentIndex: activeProjectIndex,
            projectCount: viewModel.workspaceSidebarProjects.count,
            direction: projectSwipeDirection,
            distance: abs(projectSwipeTranslation),
        )
        let hasSwipeTarget = projectSwipeDirection.flatMap { direction in
            workspaceSidebarProjectIndexAfterSwipe(
                currentIndex: activeProjectIndex,
                projectCount: viewModel.workspaceSidebarProjects.count,
                direction: direction,
            )
        } != nil
        let projectSwitchProgress = hasSwipeTarget
            ? workspaceSidebarProjectSwipeSwitchProgress(distance: abs(projectSwipeTranslation))
            : 0
        let visibleWorkspacesByProject = workspaceSidebarVisibleWorkspacesByProject(
            workspaces: viewModel.workspaceSidebarWorkspaces,
            selectedScopeId: viewModel.workspaceSidebarSelectedMonitorScopeId,
            focusedMonitorScopeId: viewModel.workspaceSidebarFocusedMonitorScopeId,
        )

        return VStack(alignment: .leading, spacing: 0) {
            if showsMonitorSelector {
                WorkspaceSidebarMonitorSelector(
                    scopes: viewModel.workspaceSidebarMonitorScopes,
                    selectedScopeId: viewModel.workspaceSidebarSelectedMonitorScopeId,
                    expansionProgress: expansionProgress,
                )
                .padding(.leading, leadingInset)
                .padding(.trailing, trailingInset)
                .padding(.top, viewModel.workspaceSidebarTopPadding)
                .padding(.bottom, 6)
            }

            projectPagerContent(
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: showsMonitorSelector ? 0 : viewModel.workspaceSidebarTopPadding,
                visibleWorkspacesByProject: visibleWorkspacesByProject,
                swipeDirection: projectSwipeDirection,
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            WorkspaceSidebarProjectPager(
                projects: viewModel.workspaceSidebarProjects,
                selectedProjectId: viewModel.workspaceSidebarSelectedProjectId,
                expansionProgress: expansionProgress,
                swipeDirection: projectSwipeDirection,
                switchProgress: projectSwitchProgress,
                edgeProgress: projectSwipeProgress,
            )
            .zIndex(2)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.top, 6)
            .padding(.bottom, 2)

            WorkspaceSidebarStatusView(
                sectionWidth: workspaceSidebarSectionWidth(expansionProgress),
                isCompact: isCompact,
            )
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.top, 8)
            .padding(.bottom, workspaceSidebarStatusBottomPadding(isCompact: isCompact))
        }
        .coordinateSpace(name: "workspaceSidebarContent")
        .onPreferenceChange(WorkspaceSidebarDropTargetPreferenceKey.self) { frames in
            WorkspaceSidebarPanel.shared.updateDropTargets(frames)
        }
        .background {
            sidebarSurface(in: sidebarShape)
        }
        .environment(\.colorScheme, .dark)
        .clipShape(sidebarShape)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(mattePanelSeparator.opacity(0.72))
                .frame(width: 0.5)
        }
        .shadow(
            color: Color.black.opacity(0.28),
            radius: 14,
            x: 2,
            y: 0
        )
        .overlay {
            WorkspaceSidebarProjectSwipeScrollCapture(
                isEnabled: !viewModel.workspaceSidebarProjects.isEmpty,
                onChanged: { horizontalTranslation, verticalTranslation in
                    handleProjectSwipeChanged(
                        horizontalTranslation: horizontalTranslation,
                        verticalTranslation: verticalTranslation,
                        expansionProgress: expansionProgress,
                    )
                },
                onEnded: { horizontalTranslation, verticalTranslation in
                    handleProjectSwipeEnded(
                        horizontalTranslation: horizontalTranslation,
                        verticalTranslation: verticalTranslation,
                        expansionProgress: expansionProgress,
                    )
                },
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
        .simultaneousGesture(projectSwipeGesture(expansionProgress: expansionProgress))
    }

    var sidebarShape: some Shape {
        Rectangle()
    }

    func sidebarSurface<S: Shape>(in shape: S) -> some View {
        shape
            .fill(mattePanelFill)
            .overlay {
                shape.stroke(mattePanelSeparator.opacity(0.34), lineWidth: 0.5)
            }
        .ignoresSafeArea()
    }

    @ViewBuilder
    func projectPagerContent(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        visibleWorkspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
        swipeDirection: Int?,
    ) -> some View {
        if viewModel.workspaceSidebarProjects.isEmpty {
            workspacePage(
                workspaces: visibleWorkspacesByProject[viewModel.workspaceSidebarSelectedProjectId] ?? [],
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                isInteractive: true,
            )
        } else {
            GeometryReader { geometry in
                let pageWidth = max(geometry.size.width, 1)
                let displayIndex = projectPagerDisplayIndex ?? 0
                let dragOffset = workspaceSidebarProjectPagerDragOffset(
                    horizontalTranslation: projectSwipeTranslation,
                    currentIndex: displayIndex,
                    projectCount: viewModel.workspaceSidebarProjects.count,
                    pageWidth: pageWidth,
                )

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(viewModel.workspaceSidebarProjects.enumerated()), id: \.element.id) { index, project in
                        if shouldRenderWorkspaceSidebarProjectPage(
                            index: index,
                            displayIndex: displayIndex,
                            swipeDirection: swipeDirection,
                            projectCount: viewModel.workspaceSidebarProjects.count,
                        ) {
                            workspacePage(
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
                }
                .offset(x: -CGFloat(displayIndex) * pageWidth + dragOffset)
                .onAppear {
                    projectPagerWidth = pageWidth
                }
                .onChange(of: pageWidth) { width in
                    projectPagerWidth = width
                }
            }
            .clipped()
        }
    }

    func workspacePage(
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
                    WorkspaceSidebarWorkspaceSection(
                        workspace: workspace,
                        dragPreview: viewModel.workspaceSidebarDropPreview,
                        expansionProgress: expansionProgress,
                        emitsDropTarget: isInteractive,
                    )
                }
                WorkspaceSidebarCreateWorkspaceSection(
                    dragPreview: viewModel.workspaceSidebarDropPreview,
                    expansionProgress: expansionProgress,
                    emitsDropTarget: isInteractive,
                    onCreateWorkspace: createWorkspaceFromSidebarButton,
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
