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
    @State var browseMode: WorkspaceSidebarBrowseMode = .activeProject
    @State var activeInUseOverrideWorkspaceName: String? = nil
    @State var isProjectMenuOpen = false
    @State var isSidebarCollapsing = false
    @State var isSidebarExpanding = false
    @State var renamingProjectId: WorkspaceProjectId? = nil
    @State var renamingProjectText = ""
    @State var renamingWorkspaceName: String? = nil
    @State var renamingWorkspaceText = ""
    @State var searchText = ""
    @State var isSearchEditing = false
    @State var searchEditingPanel: WorkspaceSidebarPanel? = nil
    @State var selectedSearchTarget: WorkspaceSidebarSearchSelection? = nil
    @State var lastProjectEdgeDragDirection: Int? = nil
    @State var lastProjectEdgeDragSwitchAt: Date = .distantPast
    @State var showsPinnedActiveWorkspaceForBrowsedProject = true

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
                finishSidebarSearch(clearText: true)
            } else if visibleWidth >= collapsedWidth + 8 {
                isSidebarCollapsing = false
            }
            if visibleWidth >= expandedWidth - 0.5 {
                isSidebarExpanding = false
                beginSidebarSearchIfNeeded()
            }
        }
        .onChange(of: snapshot.activeProjectId) { projectId in
            debugWorkspaceSidebarProjectLog(
                "snapshotActiveProjectChanged active=\(projectId.rawValue) visibleWidth=\(snapshot.visibleWidth) projects=\(snapshot.projects.map(\.id.rawValue))"
            )
            browseMode = .activeProject
            showsPinnedActiveWorkspaceForBrowsedProject = true
            activeInUseOverrideWorkspaceName = nil
            finishProjectRename(cancelled: true)
            finishSidebarSearch(clearText: true)
            resetProjectSwipeWithoutAnimation()
        }
        .onChange(of: browseMode) { mode in
            guard snapshot.visibleWidth > collapsedWidth + 0.5,
                  let panel = WorkspaceSidebarPanel.panel(for: snapshot.targetMonitorScopeId)
            else { return }
            let targetWidth = mode.isSplit ? expandedWidth * 2 : expandedWidth
            debugWorkspaceSidebarHoverLog("browseProjectWidthChange panel=\(snapshot.targetMonitorScopeId) project=\(mode.otherProjectId?.rawValue ?? "nil") snapshotWidth=\(snapshot.visibleWidth) target=\(targetWidth) frame=\(panel.frame) mouse=\(NSEvent.mouseLocation)")
            panel.cancelExpansionWork()
            panel.viewModel.isWorkspaceSidebarExpanded = true
            panel.splitBrowseCollapseSuppressedUntil = mode.isSplit ? Date().addingTimeInterval(0.65) : .distantPast
            isSidebarCollapsing = false
            isSidebarExpanding = false
            panel.animateVisibleSidebarWidth(targetWidth, animation: .easeInOut(duration: panel.animationDuration))
        }
        .onChange(of: snapshot.projects) { _ in
            if let browsedProjectId, !snapshot.projects.contains(where: { $0.id == browsedProjectId }) {
                browseMode = .activeProject
            }
            if let renamingProjectId, !snapshot.projects.contains(where: { $0.id == renamingProjectId }) {
                finishProjectRename(cancelled: true)
            }
            if let renamingWorkspaceName, !snapshot.workspaces.contains(where: { $0.name == renamingWorkspaceName }) {
                finishWorkspaceRename(cancelled: true)
            }
            isProjectMenuOpen = false
            resetProjectSwipeWithoutAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarWillCollapseNotification)) { notification in
            guard notificationPanel(from: notification)?.monitorScopeId == snapshot.targetMonitorScopeId else { return }
            guard snapshot.visibleWidth > collapsedWidth + 0.5 else {
                isSidebarCollapsing = false
                return
            }
            finishSidebarSearch(clearText: true)
            withAnimation(.easeOut(duration: 0.08)) {
                isProjectMenuOpen = false
                isSidebarCollapsing = true
                isSidebarExpanding = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarWillExpandNotification)) { notification in
            guard notificationPanel(from: notification)?.monitorScopeId == snapshot.targetMonitorScopeId else { return }
            isSidebarCollapsing = false
            isSidebarExpanding = true
            let panel = notificationPanel(from: notification)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                beginSidebarSearchIfNeeded(panel: panel)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarCommandSearchKeyNotification)) { notification in
            guard let panel = notificationPanel(from: notification),
                  panel.monitorScopeId == snapshot.targetMonitorScopeId
            else { return }
            adoptCommandSidebarSearchIfNeeded(panel: panel)
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarDismissProjectMenusNotification)) { _ in
            if isProjectMenuOpen {
                withAnimation(.easeOut(duration: 0.10)) {
                    isProjectMenuOpen = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarDragPointerChangedNotification)) { notification in
            guard let pointer = workspaceSidebarDragPointer(from: notification) else { return }
            handleProjectEdgeDrag(pointer: pointer, expansionProgress: expansionProgress)
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarDragPointerEndedNotification)) { _ in
            resetProjectEdgeDrag()
        }
    }

    func beginProjectRename(_ project: WorkspaceSidebarProjectViewModel) {
        debugWorkspaceSidebarRenameLog("beginProjectRename project=\(project.id.rawValue) displayName=\(project.displayName) active=\(snapshot.activeProjectId.rawValue) visibleWidth=\(snapshot.visibleWidth)")
        finishSidebarSearch(clearText: false)
        if project.id != snapshot.activeProjectId {
            browseMode = .split(otherProjectId: project.id)
        }
        renamingProjectId = project.id
        renamingProjectText = project.displayName
        isProjectMenuOpen = false
        currentPanel()?.prepareForInlineTextEditing()
    }

    func finishProjectRename(cancelled: Bool = false) {
        guard let projectId = renamingProjectId else { return }
        let displayName = renamingProjectText.trimmingCharacters(in: .whitespacesAndNewlines)
        debugWorkspaceSidebarRenameLog("finishProjectRename project=\(projectId.rawValue) cancelled=\(cancelled) raw=\(renamingProjectText) trimmed=\(displayName)")
        renamingProjectId = nil
        renamingProjectText = ""
        currentPanel()?.endInlineTextEditing()
        guard !cancelled, !displayName.isEmpty else { return }
        actions.send(.renameProject(projectId, displayName: displayName))
    }

    func beginWorkspaceRename(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
        debugWorkspaceSidebarRenameLog("beginWorkspaceRename workspace=\(workspace.name) displayName=\(workspace.displayName) targetScope=\(snapshot.targetMonitorScopeId) activeProject=\(snapshot.activeProjectId.rawValue) visibleWidth=\(snapshot.visibleWidth)")
        finishSidebarSearch(clearText: false)
        finishProjectRename(cancelled: true)
        renamingWorkspaceName = workspace.name
        renamingWorkspaceText = workspace.displayName
        currentPanel()?.prepareForInlineTextEditing()
    }

    func finishWorkspaceRename(cancelled: Bool = false) {
        guard let workspaceName = renamingWorkspaceName else { return }
        let displayName = renamingWorkspaceText.trimmingCharacters(in: .whitespacesAndNewlines)
        debugWorkspaceSidebarRenameLog("finishWorkspaceRename workspace=\(workspaceName) cancelled=\(cancelled) raw=\(renamingWorkspaceText) trimmed=\(displayName) targetScope=\(snapshot.targetMonitorScopeId)")
        renamingWorkspaceName = nil
        renamingWorkspaceText = ""
        currentPanel()?.endInlineTextEditing()
        guard !cancelled, !displayName.isEmpty else { return }
        actions.send(.renameWorkspace(workspaceName, displayName: displayName))
    }

    func currentPanel() -> WorkspaceSidebarPanel? {
        WorkspaceSidebarPanel.panel(for: snapshot.targetMonitorScopeId)
    }

    func beginSidebarSearchIfNeeded(panel: WorkspaceSidebarPanel? = nil) {
        guard renamingProjectId == nil, renamingWorkspaceName == nil, !isSearchEditing else { return }
        guard snapshot.visibleWidth > snapshot.configuration.collapsedWidth + 0.5 || isSidebarExpanding else { return }
        let editingPanel = panel ?? currentPanel() ?? WorkspaceSidebarPanel.shared
        adoptCommandSidebarSearchIfNeeded(panel: editingPanel)
    }

    func adoptCommandSidebarSearchIfNeeded(panel editingPanel: WorkspaceSidebarPanel) {
        guard renamingProjectId == nil, renamingWorkspaceName == nil else { return }
        if !isSearchEditing {
            isSearchEditing = true
            searchEditingPanel = editingPanel
            selectFirstSearchTarget()
        }
        let locksExpansion = editingPanel.commandExpansionLocksCollapse || editingPanel.shouldLockNextSidebarSearchExpansion
        editingPanel.shouldLockNextSidebarSearchExpansion = false
        editingPanel.beginInlineTextEditing(
            locksExpansion: locksExpansion,
            cancelsOnPointerExit: false,
            onCancel: {
                finishSidebarSearch(clearText: true)
            },
            onKeyDown: { key in
                handleSidebarSearchKey(key)
            },
        )
        let bufferedKeys = editingPanel.bufferedCommandSidebarSearchKeys
        editingPanel.bufferedCommandSidebarSearchKeys = []
        for key in bufferedKeys {
            handleSidebarSearchKey(key)
        }
    }

    func finishSidebarSearch(clearText: Bool) {
        let panel = searchEditingPanel
        if isSearchEditing {
            isSearchEditing = false
            (panel ?? currentPanel() ?? WorkspaceSidebarPanel.shared).endInlineTextEditing()
            searchEditingPanel = nil
        }
        if clearText {
            searchText = ""
        }
        selectedSearchTarget = nil
    }

    func handleSidebarSearchKey(_ key: WorkspaceSidebarInlineTextKey) {
        switch key {
            case .text(let inserted):
                searchText += inserted
                selectFirstSearchTarget()
            case .deleteBackward:
                if !searchText.isEmpty {
                    searchText.removeLast()
                }
                selectFirstSearchTarget()
            case .deleteWordBackward:
                searchText.deleteLastWord()
                selectFirstSearchTarget()
            case .deleteToBeginningOfLine:
                searchText = ""
                selectedSearchTarget = nil
            case .deleteForward:
                break
            case .commit:
                activateSelectedSearchTarget()
            case .cancel:
                let panel = searchEditingPanel ?? WorkspaceSidebarPanel.shared
                finishSidebarSearch(clearText: true)
                closeWorkspaceSidebarFromCommand(panel)
            case .moveUp:
                moveSearchSelection(delta: -1)
            case .moveDown:
                moveSearchSelection(delta: 1)
            case .ignored:
                break
        }
    }

    func selectFirstSearchTarget() {
        selectedSearchTarget = searchText.isEmpty ? nil : currentSearchSelections().first
    }

    func moveSearchSelection(delta: Int) {
        let selections = currentSearchSelections()
        guard !selections.isEmpty else {
            selectedSearchTarget = nil
            return
        }
        guard let selectedSearchTarget,
              let index = selections.firstIndex(of: selectedSearchTarget)
        else {
            self.selectedSearchTarget = selections.first
            return
        }
        let nextIndex = max(0, min(selections.count - 1, index + delta))
        self.selectedSearchTarget = selections[nextIndex]
    }

    func activateSelectedSearchTarget() {
        guard let selectedSearchTarget else { return }
        let panel = searchEditingPanel ?? WorkspaceSidebarPanel.shared
        switch selectedSearchTarget {
            case .workspace(let workspaceName):
                actions.send(.selectWorkspace(workspaceName))
            case .window(let windowId):
                actions.send(.selectWindow(windowId))
        }
        finishSidebarSearch(clearText: true)
        closeWorkspaceSidebarFromCommand(panel)
    }

    func currentSearchSelections() -> [WorkspaceSidebarSearchSelection] {
        let workspaces = currentFilteredProjectWorkspaces()
        return workspaceSidebarSearchSelections(workspaces: workspaces)
    }

    func currentFilteredProjectWorkspaces() -> [WorkspaceSidebarWorkspaceViewModel] {
        let visibleWorkspacesByProject = workspaceSidebarVisibleWorkspacesByProject(
            workspaces: snapshot.workspaces,
            selectedScopeId: snapshot.selectedMonitorScopeId,
            focusedMonitorScopeId: snapshot.focusedMonitorScopeId,
            browsedProjectId: browsedProjectId,
        )
        let filteredWorkspacesByProject = workspaceSidebarFilteredWorkspacesByProject(
            visibleWorkspacesByProject,
            projects: snapshot.projects,
            query: searchText,
        )
        let projectId: WorkspaceProjectId
        if let index = projectPagerDisplayIndex, snapshot.projects.indices.contains(index) {
            projectId = snapshot.projects[index].id
        } else {
            projectId = snapshot.activeProjectId
        }
        return filteredWorkspacesByProject[projectId] ?? []
    }
}

extension WorkspaceSidebarView {
    var browsedProjectId: WorkspaceProjectId? {
        browseMode.otherProjectId
    }
}

private func workspaceSidebarDragPointer(from notification: Notification) -> CGPoint? {
    (notification.userInfo?[workspaceSidebarDragPointerUserInfoKey] as? NSValue)?.pointValue
}

private func notificationPanel(from notification: Notification) -> WorkspaceSidebarPanel? {
    notification.object as? WorkspaceSidebarPanel
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
extension WorkspaceSidebarView {
    @ViewBuilder
    func projectPagerContent(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        visibleWorkspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
        swipeDirection: Int?,
    ) -> some View {
        if let browsedProjectId,
           browsedProjectId != snapshot.activeProjectId
        {
            splitWorkspacePage(
                activeProjectId: snapshot.activeProjectId,
                browsedProjectId: browsedProjectId,
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                visibleWorkspacesByProject: visibleWorkspacesByProject
            )
        } else if snapshot.projects.isEmpty {
            workspacePage(
                projectId: snapshot.activeProjectId,
                workspaces: visibleWorkspacesByProject[snapshot.activeProjectId] ?? [],
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                isInteractive: true,
                showsPinnedActiveWorkspace: true,
                showsCreateWorkspace: true,
                allowsActivation: allowsWorkspaceActivation(projectId: snapshot.activeProjectId),
            )
        } else {
            projectPagerPages(
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                visibleWorkspacesByProject: visibleWorkspacesByProject,
                swipeDirection: swipeDirection,
            )
        }
    }

    func projectPagerPages(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        visibleWorkspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
        swipeDirection: Int?,
    ) -> some View {
        GeometryReader { geometry in
            let pageWidth = max(geometry.size.width, 1)
            let displayIndex = projectPagerDisplayIndex ?? 0
            let dragOffset = workspaceSidebarProjectPagerDragOffset(
                horizontalTranslation: projectSwipeTranslation,
                currentIndex: displayIndex,
                projectCount: snapshot.projects.count,
                pageWidth: pageWidth,
            )

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(snapshot.projects.enumerated()), id: \.element.id) { index, project in
                    projectPageSlot(
                        index: index,
                        project: project,
                        displayIndex: displayIndex,
                        pageWidth: pageWidth,
                        expansionProgress: expansionProgress,
                        leadingInset: leadingInset,
                        trailingInset: trailingInset,
                        topPadding: topPadding,
                        visibleWorkspacesByProject: visibleWorkspacesByProject,
                        swipeDirection: swipeDirection,
                    )
                }
            }
            .offset(x: -CGFloat(displayIndex) * pageWidth + dragOffset)
            .onAppear { projectPagerWidth = pageWidth }
            .onChange(of: pageWidth) { projectPagerWidth = $0 }
        }
        .clipped()
    }
}
extension WorkspaceSidebarView {
    func projectPagerSection(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        swipeDirection: Int?,
        switchProgress: CGFloat,
        edgeProgress: CGFloat,
    ) -> some View {
        WorkspaceSidebarProjectPager(
            projects: snapshot.projects,
            selectedProjectId: snapshot.activeProjectId,
            expansionProgress: expansionProgress,
            layout: snapshot.configuration,
            isProjectMenuOpen: $isProjectMenuOpen,
            renamingProjectId: $renamingProjectId,
            renamingProjectText: $renamingProjectText,
            onSelectProject: { projectId in
                debugWorkspaceSidebarProjectLog(
                    "pagerSectionSelect project=\(projectId.rawValue) active=\(snapshot.activeProjectId.rawValue) browsed=\(browsedProjectId?.rawValue ?? "nil")"
                )
                browseMode = .activeProject
                actions.send(.selectProject(projectId))
            },
            onCreateProject: { actions.send(.createProject) },
            onBeginRenameProject: { project in
                beginProjectRename(project)
            },
            onCommitRenameProject: {
                finishProjectRename()
            },
            onCancelRenameProject: {
                finishProjectRename(cancelled: true)
            },
            onSetProjectColor: { project, colorHex in
                actions.send(.setProjectColor(project.id, colorHex: colorHex))
            },
            onDeleteProject: { project in
                actions.send(.deleteProject(project.id))
            },
        )
        .zIndex(2)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
extension WorkspaceSidebarView {
    func validProjectSwipeEndDirection(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) -> Int? {
        guard shouldHandleProjectSwipe(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
            expansionProgress: expansionProgress,
        ) else {
            return nil
        }
        return workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
        )
    }

    func finishProjectSwipeNavigation(to projectId: WorkspaceProjectId, direction: Int) {
        let startProjectId = projectSwipeStartProjectId
        let fullPageOffset = -CGFloat(direction) * max(projectPagerWidth, snapshot.configuration.expandedWidth, 1)
        withAnimation(.easeOut(duration: 0.12)) {
            projectSwipeTranslation = fullPageOffset
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard projectSwipeStartProjectId == startProjectId else { return }
            actions.send(.selectProject(projectId))
            resetProjectSwipeWithoutAnimation()
        }
    }

    func finishProjectSwipeCreation() {
        withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.9)) {
            resetProjectSwipe()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard projectSwipeStartProjectId == nil else { return }
            actions.send(.createProject)
        }
    }
}
extension WorkspaceSidebarView {
    func handleProjectSwipeEnded(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) {
        guard let direction = validProjectSwipeEndDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
            expansionProgress: expansionProgress,
        ) else {
            finishProjectSwipeSnapBack()
            return
        }
        if projectSwipeStartProjectId == nil,
           let selectedProjectIndex {
            projectSwipeStartProjectId = snapshot.projects[selectedProjectIndex].id
        }
        if finishProjectSwipeCreationIfNeeded(direction: direction, distance: abs(horizontalTranslation)) {
            return
        }
        finishProjectSwipeNavigationIfNeeded(direction: direction, distance: abs(horizontalTranslation))
    }

    func finishProjectSwipeSnapBack() {
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.9)) {
            resetProjectSwipe()
        }
    }

    private func finishProjectSwipeCreationIfNeeded(direction: Int, distance: CGFloat) -> Bool {
        guard shouldCreateWorkspaceSidebarProjectAfterSwipe(
            currentIndex: projectPagerDisplayIndex,
            projectCount: snapshot.projects.count,
            direction: direction,
            distance: distance,
        ) else {
            return false
        }
        performWorkspaceSidebarProjectHaptic(.levelChange)
        finishProjectSwipeCreation()
        return true
    }

    private func finishProjectSwipeNavigationIfNeeded(direction: Int, distance: CGFloat) {
        guard let nextIndex = workspaceSidebarProjectIndexAfterSwipe(
            currentIndex: projectPagerDisplayIndex,
            projectCount: snapshot.projects.count,
            direction: direction,
        ), distance >= workspaceSidebarProjectSwipeNavigateThreshold else {
            performWorkspaceSidebarProjectHaptic(.alignment)
            finishProjectSwipeSnapBack()
            return
        }
        finishProjectSwipeNavigation(to: snapshot.projects[nextIndex].id, direction: direction)
    }
}
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
        resetProjectEdgeDrag()
    }

    func resetProjectEdgeDrag() {
        lastProjectEdgeDragDirection = nil
        lastProjectEdgeDragSwitchAt = .distantPast
    }

}
extension WorkspaceSidebarView {
    func monitorSelectorSection(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
    ) -> some View {
        WorkspaceSidebarMonitorSelector(
            scopes: snapshot.monitorScopes,
            projects: snapshot.projects,
            selectedScopeId: snapshot.selectedMonitorScopeId,
            activeProjectId: snapshot.activeProjectId,
            browsedProjectId: browsedProjectId,
            expansionProgress: expansionProgress,
            sectionWidth: workspaceSidebarTopSectionWidth(expansionProgress: expansionProgress),
            onSelectScope: { scopeId in
                if scopeId == workspaceSidebarDefaultScopeId {
                    browseMode = .activeProject
                }
                actions.send(.selectMonitorScope(scopeId))
            },
            onSelectProject: { projectId in
                WorkspaceSidebarPanel.panel(for: snapshot.targetMonitorScopeId)?.cancelExpansionWork()
                browseMode = projectId.map { .split(otherProjectId: $0) } ?? .activeProject
                showsPinnedActiveWorkspaceForBrowsedProject = false
            },
            onRenameProject: { project in
                beginProjectRename(project)
            },
            renamingProjectId: $renamingProjectId,
            renamingProjectText: $renamingProjectText,
            onCommitRenameProject: {
                finishProjectRename()
            },
            onCancelRenameProject: {
                finishProjectRename(cancelled: true)
            },
            onSetProjectColor: { project, colorHex in
                actions.send(.setProjectColor(project.id, colorHex: colorHex))
            },
            onDeleteProject: { project in
                actions.send(.deleteProject(project.id))
            },
        )
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, snapshot.configuration.topPadding)
        .padding(.bottom, workspaceSidebarSectionGap)
        .zIndex(100)
    }

    func workspaceSidebarTopSectionWidth(expansionProgress: CGFloat) -> CGFloat {
        if browsedProjectId != nil {
            return workspaceSidebarSplitSectionWidth(expansionProgress: expansionProgress)
        }
        return workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration)
    }

    func statusSection(
        expansionProgress: CGFloat,
        isCompact: Bool,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
    ) -> some View {
        WorkspaceSidebarStatusView(
            sectionWidth: workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration),
            isCompact: isCompact,
            showsSeconds: snapshot.configuration.showsSeconds,
            showsDate: snapshot.configuration.showsDate,
            showsWeekday: snapshot.configuration.showsWeekday,
        )
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, 4)
        .padding(.bottom, workspaceSidebarStatusBottomPadding(isCompact: isCompact) + 4)
    }

    func sidebarSearchSection(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.66))
                .frame(width: 14)

            Text(searchText)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                finishSidebarSearch(clearText: true)
                beginSidebarSearchIfNeeded()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Clear search")
        }
        .padding(.horizontal, 8)
        .frame(width: workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration), height: workspaceSidebarSearchHeight)
        .background {
            RoundedRectangle(cornerRadius: workspaceSidebarDropdownCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.11))
        }
        .overlay {
            RoundedRectangle(cornerRadius: workspaceSidebarDropdownCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.bottom, workspaceSidebarSectionGap)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
extension WorkspaceSidebarView {
    var sidebarShape: some Shape {
        WorkspaceSidebarPanelShape(rightCornerRadius: workspaceSidebarPanelRightCornerRadius)
    }

    func sidebarSurface<S: Shape>(in shape: S) -> some View {
        // The sidebar meets the display edge, so an outline around all four sides reads as a
        // second, lighter panel behind the content. Keep the material flat and use only the
        // trailing separator to define its boundary.
        GlassSurface(
            shape: shape,
            hasBorder: false,
            style: snapshot.configuration.chromeStyle,
            solidColor: snapshot.configuration.resolvedSolidChromeColor,
        )
        // This panel has no safe-area inset. Expanding the material here gives the native
        // glass backing layer a rectangular area outside the rounded trailing corners.
        .clipShape(shape)
    }

    func sidebarSwipeCaptureOverlay(expansionProgress: CGFloat) -> some View {
        WorkspaceSidebarProjectSwipeScrollCapture(
            isEnabled: !snapshot.projects.isEmpty,
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
}

private struct WorkspaceSidebarPanelShape: Shape {
    let rightCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(rightCornerRadius, rect.width / 2, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
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
                showsPinnedActiveWorkspace: showsPinnedActiveWorkspaceForBrowsedProject,
                showsCreateWorkspace: browsedProjectId == nil,
                allowsActivation: allowsWorkspaceActivation(projectId: project.id),
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
        showsPinnedActiveWorkspace: Bool = true,
        showsCreateWorkspace: Bool = true,
        allowsActivation: Bool? = nil,
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if showsPinnedActiveWorkspace,
                   let pinnedActiveWorkspace = pinnedActiveWorkspace(
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
                        allowsWorkspaceActivation: allowsActivation ?? allowsWorkspaceActivation(projectId: projectId),
                        isPinnedActiveWorkspace: false,
                        projectContextLabel: browsedProjectId != nil && projectId != snapshot.activeProjectId ? projectName(projectId) : nil,
                        projectContextColor: browsedProjectId != nil && projectId != snapshot.activeProjectId ? projectColor(projectId) : nil
                    )
                }
                if showsCreateWorkspace && workspaceSidebarShowsCreateWorkspace(selectedScopeId: snapshot.selectedMonitorScopeId) {
                    let createMonitorScopeId = workspaceSidebarWorkspaceCreateScope(
                        selectedScopeId: snapshot.selectedMonitorScopeId,
                        targetMonitorScopeId: snapshot.targetMonitorScopeId,
                        focusedScopeId: snapshot.focusedMonitorScopeId,
                    )
                    WorkspaceSidebarCreateWorkspaceSection(
                        projectId: projectId,
                        monitorScopeId: createMonitorScopeId,
                        dragPreview: snapshot.dropPreview,
                        expansionProgress: expansionProgress,
                        layout: snapshot.configuration,
                        emitsDropTarget: true,
                        onCreateWorkspace: {
                            actions.send(.createWorkspace(
                                projectId: projectId,
                                monitorScopeId: createMonitorScopeId
                            ))
                        },
                        onDropPayload: { payload in
                            switch payload {
                                case .window(let windowId):
                                    actions.send(.moveWindowToNewWorkspace(
                                        windowId,
                                        projectId: projectId,
                                        monitorScopeId: createMonitorScopeId,
                                    ))
                                case .tabGroup(let representativeWindowId):
                                    actions.send(.moveTabGroupToNewWorkspace(
                                        representativeWindowId,
                                        projectId: projectId,
                                        monitorScopeId: createMonitorScopeId,
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

    func splitWorkspacePage(
        activeProjectId: WorkspaceProjectId,
        browsedProjectId: WorkspaceProjectId,
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        visibleWorkspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
    ) -> some View {
        let sectionWidth = workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration)
        return HStack(alignment: .top, spacing: workspaceSidebarSplitPaneGap) {
            workspacePage(
                projectId: activeProjectId,
                workspaces: visibleWorkspacesByProject[activeProjectId] ?? [],
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: 0,
                topPadding: topPadding,
                isInteractive: true,
                showsPinnedActiveWorkspace: false,
                showsCreateWorkspace: true,
                allowsActivation: true,
            )
            .frame(width: sectionWidth + leadingInset, alignment: .topLeading)

            workspacePage(
                projectId: browsedProjectId,
                workspaces: visibleWorkspacesByProject[browsedProjectId] ?? [],
                expansionProgress: expansionProgress,
                leadingInset: 0,
                trailingInset: trailingInset,
                topPadding: topPadding,
                isInteractive: true,
                showsPinnedActiveWorkspace: false,
                showsCreateWorkspace: true,
                allowsActivation: false,
            )
            .frame(width: sectionWidth + trailingInset, alignment: .topLeading)
        }
        .frame(
            width: workspaceSidebarSplitSectionWidth(expansionProgress: expansionProgress) + leadingInset + trailingInset,
            alignment: .topLeading
        )
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
        let isFromOtherDisplay = false
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
            isOnFocusedMonitor: workspace.monitorScopeId == snapshot.focusedMonitorScopeId,
            allowsWorkspaceActivation: allowsWorkspaceActivation,
            isPinnedActiveWorkspace: isPinnedActiveWorkspace,
            isActiveOnTargetMonitor: workspace.monitorScopeId == snapshot.targetMonitorScopeId && workspace.isVisible,
            projectContextLabel: projectContextLabel,
            projectContextColor: projectContextColor,
            renamingWorkspaceName: $renamingWorkspaceName,
            renamingWorkspaceText: $renamingWorkspaceText,
            onBeginRenameWorkspace: {
                beginWorkspaceRename(workspace)
            },
            onCommitRenameWorkspace: {
                finishWorkspaceRename()
            },
            onCancelRenameWorkspace: {
                finishWorkspaceRename(cancelled: true)
            },
            selectedSearchTarget: searchText.isEmpty ? nil : selectedSearchTarget,
            isSearchFiltering: !searchText.isEmpty,
            activeInUseOverrideWorkspaceName: $activeInUseOverrideWorkspaceName,
            actions: actions,
        )
    }

    func allowsWorkspaceActivation(projectId: WorkspaceProjectId) -> Bool {
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
