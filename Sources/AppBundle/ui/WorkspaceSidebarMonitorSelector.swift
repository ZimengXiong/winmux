import AppKit
import Common
import SwiftUI

// MARK: - Monitor Selector

struct WorkspaceSidebarMonitorSelector: View {
    let scopes: [WorkspaceSidebarMonitorScopeViewModel]
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedScopeId: String
    let activeProjectId: WorkspaceProjectId
    let browsedProjectId: WorkspaceProjectId?
    let expansionProgress: CGFloat
    let sectionWidth: CGFloat
    var onSelectScope: (String) -> Void = { selectWorkspaceSidebarMonitorScope($0) }
    var onSelectProject: (WorkspaceProjectId) -> Void = { _ in }
    var onCreateProject: () -> Void = {}
    var onRenameProject: (WorkspaceSidebarProjectViewModel) -> Void = { _ in }
    @Binding var renamingProjectId: WorkspaceProjectId?
    @Binding var renamingProjectText: String
    var onCommitRenameProject: @MainActor @Sendable () -> Void = {}
    var onCancelRenameProject: @MainActor @Sendable () -> Void = {}
    var onSetProjectColor: (WorkspaceSidebarProjectViewModel, String?) -> Void = { _, _ in }
    var onDeleteProject: (WorkspaceSidebarProjectViewModel) -> Void = { _ in }

    @State private var isProjectMenuOpen = false
    private var projectPopupWidth: CGFloat {
        let names = browsableProjects.map(\.displayName) + ["Other Projects"]
        let maxTextWidth = names.map {
            ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width
        }.max() ?? 0
        return max(ceil(maxTextWidth) + 50, 148)
    }
    private var hasMultipleMonitors: Bool {
        scopes.count { workspaceSidebarMonitorScopePoint($0.id) != nil } > 1
    }

    private var quickScopes: [WorkspaceSidebarMonitorScopeViewModel] {
        var result = [
            scopes.first { $0.id == workspaceSidebarDefaultScopeId }
                ?? WorkspaceSidebarMonitorScopeViewModel(
                    id: workspaceSidebarDefaultScopeId,
                    displayName: "Default",
                    subtitle: nil,
                    systemImageName: "display",
                    isFocusedMonitor: false
                ),
            scopes.first { $0.id == workspaceSidebarFocusedScopeId }
                ?? WorkspaceSidebarMonitorScopeViewModel(
                    id: workspaceSidebarFocusedScopeId,
                    displayName: "Focus",
                    subtitle: nil,
                    systemImageName: "scope",
                    isFocusedMonitor: false
                ),
        ]
        if hasMultipleMonitors {
            result.append(
                scopes.first { $0.id == workspaceSidebarAllScopeId }
                    ?? WorkspaceSidebarMonitorScopeViewModel(
                        id: workspaceSidebarAllScopeId,
                        displayName: "All",
                        subtitle: nil,
                        systemImageName: "rectangle.grid.2x2",
                        isFocusedMonitor: false
                    )
            )
        }
        return result
    }

    private var selectedProject: WorkspaceSidebarProjectViewModel? {
        guard let browsedProjectId else { return nil }
        return projects.first { $0.id == browsedProjectId }
    }

    private var browsableProjects: [WorkspaceSidebarProjectViewModel] {
        projects.filter { $0.id != activeProjectId }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(quickScopes.enumerated()), id: \.element.id) { index, scope in
                monitorScopePill(scope)
                if index == 1, !browsableProjects.isEmpty {
                    projectSelector
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: sectionWidth, alignment: .leading)
        .frame(height: workspaceSidebarDropdownHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(expansionProgress)
        .zIndex(isProjectMenuOpen ? 200 : 0)
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarWillCollapseNotification)) { _ in
            if isProjectMenuOpen {
                withAnimation(.easeOut(duration: 0.08)) {
                    isProjectMenuOpen = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarDismissProjectMenusNotification)) { _ in
            if isProjectMenuOpen {
                withAnimation(.easeOut(duration: 0.10)) {
                    isProjectMenuOpen = false
                }
            }
        }
    }

    private func monitorScopePill(_ scope: WorkspaceSidebarMonitorScopeViewModel) -> some View {
        let isActive = scope.id == selectedScopeId && browsedProjectId == nil
        return Button {
            isProjectMenuOpen = false
            onSelectScope(scope.id)
        } label: {
            Text(scope.id == workspaceSidebarFocusedScopeId ? "Focus" : scope.displayName)
                .font(.system(size: workspaceSidebarDropdownLabelSize, weight: isActive ? .semibold : .medium))
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.68))
                .modifier(WorkspaceSidebarDropdownControlStyle(isActive: isActive))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(scopeAccessibilityLabel(scope))
        .background {
            if workspaceSidebarMonitorScopePoint(scope.id) != nil {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: WorkspaceSidebarDropTargetPreferenceKey.self,
                        value: [WorkspaceSidebarDropTargetFrame(
                            kind: .monitor(scope.id),
                            frame: geometry.frame(in: .named("workspaceSidebarContent")),
                        )],
                    )
                }
            }
        }
    }

    private var projectSelector: some View {
        let isActive = selectedProject != nil || isProjectMenuOpen
        if let selectedProject, renamingProjectId == selectedProject.id {
            return AnyView(
                WorkspaceSidebarProjectRenameField(
                    project: selectedProject,
                    text: $renamingProjectText,
                    onCommit: onCommitRenameProject,
                    onCancel: onCancelRenameProject,
                )
                .frame(width: projectPopupWidth, height: workspaceSidebarDropdownHeight)
            )
        }
        return AnyView(Button {
            guard !browsableProjects.isEmpty else { return }
            isProjectMenuOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(selectedProject?.displayName ?? "Other Projects")
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isProjectMenuOpen ? 180 : 0))
            }
            .foregroundStyle(Color.white.opacity(isActive ? 0.86 : 0.72))
            .modifier(WorkspaceSidebarDropdownControlStyle(isActive: isActive))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .overlay(alignment: .topTrailing) {
            projectPopup
                .offset(y: workspaceSidebarDropdownHeight + workspaceSidebarSectionGap)
        }
        .zIndex(isProjectMenuOpen ? 200 : 0)
        .help("Browse project workspaces")
        )
    }

    private var projectPopup: some View {
        Group {
            if isProjectMenuOpen {
                WorkspaceSidebarProjectPopup(
                    projects: browsableProjects,
                    selectedProjectId: browsedProjectId ?? activeProjectId,
                    onSelect: { projectId in
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            onSelectProject(projectId)
                        }
                    },
                    onCreate: {
                        onCreateProject()
                        isProjectMenuOpen = false
                    },
                    onRename: { project in
                        onRenameProject(project)
                        isProjectMenuOpen = false
                    },
                    onSetColor: onSetProjectColor,
                    onDelete: { project in
                        onDeleteProject(project)
                        isProjectMenuOpen = false
                    },
                    showsCreateAction: false,
                    menuWidth: projectPopupWidth
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)),
                    removal: .opacity
                ))
                .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.88), value: isProjectMenuOpen)
                .zIndex(200)
            }
        }
    }

    private func scopeAccessibilityLabel(_ scope: WorkspaceSidebarMonitorScopeViewModel) -> String {
        if let subtitle = scope.subtitle {
            return "\(scope.displayName), \(subtitle)"
        }
        return scope.displayName
    }
}
