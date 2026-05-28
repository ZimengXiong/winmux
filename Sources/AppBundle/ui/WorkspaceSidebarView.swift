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
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarWillCollapseNotification)) { _ in
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
            isSidebarCollapsing = false
            isSidebarExpanding = true
            let panel = notificationPanel(from: notification)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                beginSidebarSearchIfNeeded(panel: panel)
            }
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

    func beginWorkspaceRename(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
        debugWorkspaceSidebarRenameLog("beginWorkspaceRename workspace=\(workspace.name) displayName=\(workspace.displayName) targetScope=\(snapshot.targetMonitorScopeId) activeProject=\(snapshot.activeProjectId.rawValue) visibleWidth=\(snapshot.visibleWidth)")
        finishSidebarSearch(clearText: false)
        finishProjectRename(cancelled: true)
        renamingWorkspaceName = workspace.name
        renamingWorkspaceText = workspace.displayName
    }

    func finishWorkspaceRename(cancelled: Bool = false) {
        guard let workspaceName = renamingWorkspaceName else { return }
        let displayName = renamingWorkspaceText.trimmingCharacters(in: .whitespacesAndNewlines)
        debugWorkspaceSidebarRenameLog("finishWorkspaceRename workspace=\(workspaceName) cancelled=\(cancelled) raw=\(renamingWorkspaceText) trimmed=\(displayName) targetScope=\(snapshot.targetMonitorScopeId)")
        renamingWorkspaceName = nil
        renamingWorkspaceText = ""
        guard !cancelled, !displayName.isEmpty else { return }
        actions.send(.renameWorkspace(workspaceName, displayName: displayName))
    }

    func beginSidebarSearchIfNeeded(panel: WorkspaceSidebarPanel? = nil) {
        guard renamingProjectId == nil, renamingWorkspaceName == nil, !isSearchEditing else { return }
        guard snapshot.visibleWidth > snapshot.configuration.collapsedWidth + 0.5 || isSidebarExpanding else { return }
        isSearchEditing = true
        let editingPanel = panel ?? WorkspaceSidebarPanel.shared
        searchEditingPanel = editingPanel
        selectFirstSearchTarget()
        editingPanel.beginInlineTextEditing(
            locksExpansion: false,
            cancelsOnPointerExit: false,
            onCancel: {
                finishSidebarSearch(clearText: true)
            },
            onKeyDown: { key in
                handleSidebarSearchKey(key)
            },
        )
    }

    func finishSidebarSearch(clearText: Bool) {
        let panel = searchEditingPanel
        if isSearchEditing {
            isSearchEditing = false
            (panel ?? WorkspaceSidebarPanel.shared).endInlineTextEditing()
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
