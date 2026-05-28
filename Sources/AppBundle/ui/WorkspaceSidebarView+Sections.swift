import Common
import SwiftUI

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
            showsDate: snapshot.configuration.showsDate,
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
