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

    @State private var isProjectMenuOpen = false
    @State private var projectSelectorLeading: CGFloat = 0
    private let projectPopupWidth: CGFloat = 148
    private let coordinateSpaceName = "WorkspaceSidebarMonitorSelector"

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
        if concreteMonitorScopeCount > 1 {
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

    private var concreteMonitorScopeCount: Int {
        scopes.filter { !workspaceSidebarMonitorScopeIsSentinel($0.id) }.count
    }

    private var selectedProject: WorkspaceSidebarProjectViewModel? {
        guard let browsedProjectId else { return nil }
        return projects.first { $0.id == browsedProjectId }
    }

    private var otherProjects: [WorkspaceSidebarProjectViewModel] {
        projects.filter { $0.id != activeProjectId }
    }

    private var selectedProjectColor: Color {
        guard let selectedProject else { return Color.accentColor }
        return workspaceSidebarProjectColor(projectId: selectedProject.id, configuredHex: selectedProject.colorHex)
    }

    private var projectPopupHeight: CGFloat {
        let rowCount = CGFloat(otherProjects.count)
        let popupPadding = (workspaceSidebarMenuRowSpacing + 1) * 2
        let rowSpacing = CGFloat(max(otherProjects.count - 1, 0)) * workspaceSidebarMenuRowSpacing
        return (rowCount * workspaceSidebarMenuRowHeight) + rowSpacing + popupPadding
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(quickScopes.enumerated()), id: \.element.id) { index, scope in
                        monitorScopePill(scope)
                        if index == 1, !otherProjects.isEmpty {
                            projectSelector
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minWidth: sectionWidth, alignment: .leading)
            }
            .frame(height: workspaceSidebarDropdownHeight)

            if isProjectMenuOpen {
                projectPopup
                    .offset(y: workspaceSidebarDropdownHeight + workspaceSidebarSectionGap)
            }
        }
        .frame(
            height: workspaceSidebarDropdownHeight + (isProjectMenuOpen ? workspaceSidebarSectionGap + projectPopupHeight : 0),
            alignment: .topLeading
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: coordinateSpaceName)
        .onPreferenceChange(WorkspaceSidebarProjectSelectorLeadingKey.self) { leading in
            projectSelectorLeading = leading
        }
        .opacity(expansionProgress)
    }

    private func monitorScopePill(_ scope: WorkspaceSidebarMonitorScopeViewModel) -> some View {
        let isActive = scope.id == selectedScopeId && browsedProjectId == nil
        return Button {
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
        Button {
            isProjectMenuOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(selectedProject?.displayName ?? "Other Projects")
                    .font(.system(size: workspaceSidebarDropdownLabelSize, weight: selectedProject == nil ? .medium : .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.72)
            }
            .foregroundStyle(selectedProject == nil ? Color.white.opacity(0.68) : Color.white)
            .modifier(WorkspaceSidebarDropdownControlStyle(
                isActive: selectedProject != nil,
                activeFill: selectedProjectColor.opacity(0.38),
                activeStroke: selectedProjectColor.opacity(0.58)
            ))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WorkspaceSidebarProjectSelectorLeadingKey.self,
                    value: proxy.frame(in: .named(coordinateSpaceName)).minX
                )
            }
        }
        .help("Browse project workspaces")
    }

    private var projectPopup: some View {
        WorkspaceSidebarProjectPopup(
            projects: otherProjects,
            selectedProjectId: browsedProjectId ?? WorkspaceProjectId(rawValue: ""),
            onSelect: { projectId in
                onSelectProject(projectId)
                isProjectMenuOpen = false
            },
            onCreate: {},
            onRename: { _ in },
            onSetColor: { _, _ in },
            onDelete: { _ in },
            showsCreateAction: false,
            allowsContextMenu: false,
            menuWidth: projectPopupWidth
        )
        .padding(.leading, min(projectSelectorLeading, max(sectionWidth - projectPopupWidth, 0)))
        .zIndex(200)
    }

    private func scopeAccessibilityLabel(_ scope: WorkspaceSidebarMonitorScopeViewModel) -> String {
        if let subtitle = scope.subtitle {
            return "\(scope.displayName), \(subtitle)"
        }
        return scope.displayName
    }
}

private struct WorkspaceSidebarProjectSelectorLeadingKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
