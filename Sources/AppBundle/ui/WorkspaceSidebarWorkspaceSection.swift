import AppKit
import Common
import SwiftUI

struct WorkspaceSidebarWorkspaceSection: View {
    let workspace: WorkspaceSidebarWorkspaceViewModel
    let dragPreview: WorkspaceSidebarDropPreviewViewModel?
    let expansionProgress: CGFloat
    let emitsDropTarget: Bool

    @State var isHovered = false
    @State var hoveredWindowId: UInt32? = nil
    @State var isEditingName = false
    @State var editingNameDraft = ""
    @Namespace var rowHoverNamespace
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let headerHeight: CGFloat = 26
    let rowHeight: CGFloat = 23

    var contentWidth: CGFloat { workspaceSidebarContentWidth(expansionProgress) }
    var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress) }
    var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    var showsWindowRows: Bool { expansionProgress >= workspaceSidebarRowsRevealProgress }
    var isDropTarget: Bool { dragPreview?.targetWorkspaceName == workspace.name }
    var activeSidebarDragSourceWindowId: UInt32? { dragPreview?.sourceWindowId }
    var sectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }

    var body: some View {
        interactiveSectionContent
            .padding(.vertical, isCompact ? 4 : 5)
            .padding(.horizontal, workspaceSidebarSectionInnerHorizontalInset)
            .frame(width: sectionWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .contextMenu {
                Button("Rename Workspace") {
                    beginInlineRename()
                }
                Button("Reset Workspace Name") {
                    resetWorkspaceNameFromSidebar(workspace)
                }
                Button(role: .destructive) {
                    deleteWorkspaceFromSidebar(workspace)
                } label: {
                    Text("Delete Workspace")
                }
            }
            .onHover { hover in
                isHovered = hover
                TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = nextWorkspaceSidebarHoveredWorkspaceName(
                    currentHoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
                    workspaceName: workspace.name,
                    isHovering: hover,
                )
            }
            .zIndex(isDropTarget ? 1 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: dragPreview)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: expansionProgress)
            .animation(reduceMotion ? workspaceSidebarReducedMotionHoverAnimation : workspaceSidebarHoverAnimation, value: isHovered)
            .animation(reduceMotion ? workspaceSidebarReducedMotionHoverAnimation : workspaceSidebarHoverAnimation, value: hoveredWindowId)
            .background {
                ZStack {
                    sectionBackground
                    if !isCompact {
                        sectionActivationButton
                    }
                }
            }
            .shadow(
                color: isDropTarget ? Color.accentColor.opacity(0.18) : .clear,
                radius: isDropTarget ? 12 : 0
            )
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: WorkspaceSidebarDropTargetPreferenceKey.self,
                        value: emitsDropTarget ? [WorkspaceSidebarDropTargetFrame(
                            kind: .workspace(workspace.name),
                            frame: geometry.frame(in: .named("workspaceSidebarContent")),
                        )] : [],
                    )
                }
            }
    }

    func handleSectionClick() {
        if shouldHandleWorkspaceSidebarActivation(isEditing: isEditingName, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) {
            focusWorkspaceFromSidebar(workspace.name)
        }
    }

    func beginInlineRename() {
        WorkspaceSidebarPanel.shared.beginInlineTextEditing()
        isEditingName = true
        editingNameDraft = workspace.displayName
    }

    func commitInlineRename() {
        guard isEditingName else { return }
        let trimmed = editingNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingName = false
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
        guard !trimmed.isEmpty, trimmed != workspace.displayName else { return }
        renameWorkspaceFromSidebar(workspace, displayName: trimmed)
    }

    func cancelInlineRename() {
        isEditingName = false
        editingNameDraft = ""
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
    }

    @ViewBuilder
    var interactiveSectionContent: some View {
        if isCompact {
            Button(action: handleSectionClick) {
                sectionContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .contentShape(sectionShape)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(sectionShape)
        } else {
            sectionContent
                .contentShape(sectionShape)
        }
    }

    var sectionActivationButton: some View {
        Button(action: handleSectionClick) {
            Color.clear
                .contentShape(sectionShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(workspace.displayName)
    }

    var sectionContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Group {
                if isCompact {
                    header
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if isEditingName {
                    header
                } else {
                    headerButton
                }
            }
                .frame(height: headerHeight)
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
            windowRows
            dropPreviewRow
        }
    }

    var headerButton: some View {
        Button(action: handleSectionClick) {
            header
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    beginInlineRename()
                },
        )
    }

    @ViewBuilder
    var windowRows: some View {
        if showsWindowRows, !workspace.items.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(workspace.items) { item in
                    workspaceItemView(item)
                }
            }
            .padding(.leading, workspaceSidebarWindowRowsLeadingIndent)
        }
    }

    @ViewBuilder
    func workspaceItemView(_ item: WorkspaceSidebarItemViewModel) -> some View {
        switch item.kind {
            case .window(let window):
                workspaceWindowButton(window, allowsDrag: true)
            case .tabGroup(let group):
                workspaceTabGroupView(group)
        }
    }

    @ViewBuilder
    var dropPreviewRow: some View {
        if dragPreview?.targetWorkspaceName == workspace.name {
            WorkspaceSidebarPreviewRow(
                preview: dragPreview.orDie(),
                expansionProgress: expansionProgress,
                rowHeight: rowHeight,
                expandedContentWidth: contentWidth
            )
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
                removal: .identity,
            ))
        }
    }

    func workspaceWindowButton(
        _ window: WorkspaceSidebarWindowViewModel,
        allowsDrag: Bool,
        subject: WindowDragSubject = .window,
        leadingHitInset: CGFloat = 0,
    ) -> some View {
        Button {
            guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
            focusWindowFromSidebar(window.windowId, fallbackWorkspace: window.workspaceName)
        } label: {
                WorkspaceSidebarWindowRow(
                    title: window.title ?? window.appName,
                    badge: nil,
                    isFocused: window.isFocused,
                    rowHeight: rowHeight,
                    isHovered: hoveredWindowId == window.windowId,
                    style: .window,
                    hoverNamespace: rowHoverNamespace,
                )
            .padding(.leading, leadingHitInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(WorkspaceSidebarOptionalDragModifier(
            isEnabled: allowsDrag,
            onChanged: {
                updateSidebarWindowDrag(window.windowId, subject: subject)
            },
            onEnded: {
                finishSidebarWindowDrag()
            },
        ))
        .onHover { hover in
            hoveredWindowId = nextWorkspaceSidebarHoveredWindowId(
                currentHoveredWindowId: hoveredWindowId,
                windowId: window.windowId,
                isHovering: hover,
            )
        }
        .opacity(activeSidebarDragSourceWindowId == window.windowId ? 0.25 : 1)
        .scaleEffect(activeSidebarDragSourceWindowId == window.windowId ? 0.94 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: activeSidebarDragSourceWindowId == window.windowId)
    }

    func workspaceTabGroupView(_ group: WorkspaceSidebarTabGroupViewModel) -> some View {
        let isDragging = activeSidebarDragSourceWindowId == group.representativeWindowId
        let groupHoverId = UInt32.max - group.representativeWindowId
        return VStack(alignment: .leading, spacing: 1) {
            Button {
                guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
                focusWindowFromSidebar(group.representativeWindowId, fallbackWorkspace: group.workspaceName)
            } label: {
                WorkspaceSidebarWindowRow(
                    title: group.title.isEmpty ? "Tab Group" : group.title,
                    badge: group.windowCount > 1 ? "\(group.windowCount)" : nil,
                    isFocused: group.isFocused,
                    rowHeight: rowHeight,
                    isHovered: hoveredWindowId == groupHoverId,
                    style: .tabGroupHeader,
                    hoverNamespace: rowHoverNamespace,
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(WorkspaceSidebarOptionalDragModifier(
                isEnabled: true,
                onChanged: {
                    updateSidebarWindowDrag(group.representativeWindowId, subject: .group)
                },
                onEnded: {
                    finishSidebarWindowDrag()
                },
            ))
            .onHover { hover in
                hoveredWindowId = nextWorkspaceSidebarHoveredWindowId(
                    currentHoveredWindowId: hoveredWindowId,
                    windowId: groupHoverId,
                    isHovering: hover,
                )
            }
            .opacity(isDragging ? 0.25 : 1)
            .scaleEffect(isDragging ? 0.94 : 1)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(group.tabs) { tab in
                    workspaceWindowButton(tab, allowsDrag: true, subject: .window, leadingHitInset: 14)
                }
            }
            .opacity(isDragging ? 0.4 : 1)
        }
        .padding(.vertical, 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: isDragging)
    }

    // MARK: - Section Background

    var sectionBackground: some View {
        sectionShape
            .fill(sectionBackgroundFill)
            .overlay {
                sectionShape
                    .strokeBorder(sectionBorderColor, lineWidth: sectionBorderWidth)
            }
    }

    // MARK: - Header

    var header: some View {
        Group {
            if isEditingName && !isCompact {
                workspaceRenameEditor
            } else if isCompact {
                workspaceBadge
                    .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace.displayName)
                        .font(.system(size: 14, weight: workspace.isFocused ? .bold : .semibold))
                        .foregroundStyle(workspace.isFocused ? Color.white.opacity(0.96) : Color.white.opacity(0.86))
                        .lineLimit(1)
                    if let monitorName = workspace.monitorName, showsWindowRows {
                        Text(monitorName)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.48))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, workspaceSidebarHeaderLeadingPadding)
                .padding(.trailing, workspaceSidebarRowHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var workspaceRenameEditor: some View {
        WorkspaceSidebarProjectRenameField(
            text: $editingNameDraft,
            focusId: "workspace:\(workspace.name)",
            alignment: .left,
            fontSize: 14,
            fontWeight: .semibold,
            onCommit: commitInlineRename,
            onCancel: cancelInlineRename,
        )
            .padding(.horizontal, 5)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(workspaceSidebarActiveWorkspaceTint.opacity(0.48), lineWidth: 0.6)
                    }
            )
            .padding(.leading, workspaceSidebarHeaderLeadingPadding)
            .padding(.trailing, workspaceSidebarRowHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var sectionBackgroundFill: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.13)
        } else if workspace.isFocused {
            return workspaceSidebarActiveWorkspaceTint.opacity(isCompact ? 0.32 : 0.17)
        } else if isCompact {
            if isHovered {
                return Color.white.opacity(0.06)
            }
        } else if isHovered {
            return Color.white.opacity(0.045)
        } else if workspace.isVisible && expansionProgress > 0.5 {
            return Color.white.opacity(0.02)
        }
        return Color.clear
    }

    var sectionBorderColor: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.46)
        }
        if workspace.isFocused {
            return workspaceSidebarActiveWorkspaceTint.opacity(isCompact ? 0.70 : 0.42)
        }
        if isHovered || workspace.isVisible {
            return mattePanelSeparator.opacity(isCompact ? 0.32 : 0.24)
        }
        return Color.clear
    }

    var sectionBorderWidth: CGFloat {
        if isDropTarget {
            return 1.5
        }
        if workspace.isFocused {
            return isCompact ? 0.9 : 0.7
        }
        if isHovered || workspace.isVisible {
            return 0.6
        }
        return 0.5
    }

    var workspaceBadge: some View {
        Text(workspaceBadgeText)
            .font(.custom("Arial", size: isCompact ? 12 : 15).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(workspaceBadgeForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth, alignment: .center)
    }

    var workspaceBadgeText: String {
        if workspace.isGeneratedName, workspace.sidebarLabel.isEmpty {
            return generatedWorkspaceBadgeText
        }
        if workspace.isGeneratedName, let initial = workspace.displayName.first {
            return String(initial).uppercased()
        }
        return workspace.displayName.first.map { String($0).uppercased() } ?? "W"
    }

    var generatedWorkspaceBadgeText: String {
        let prefix = "Workspace "
        if workspace.displayName.hasPrefix(prefix) {
            let suffix = String(workspace.displayName.dropFirst(prefix.count))
            if !suffix.isEmpty {
                return suffix
            }
        }
        return workspace.displayName.first.map { String($0).uppercased() } ?? "W"
    }

    var workspaceBadgeForeground: Color {
        if workspace.isFocused {
            return isCompact ? Color.white.opacity(0.92) : Color.white.opacity(0.90)
        }
        return Color.white.opacity(isCompact ? 0.72 : 0.54)
    }
}

struct WorkspaceSidebarOptionalDragModifier: ViewModifier {
    let isEnabled: Bool
    let onChanged: () -> Void
    let onEnded: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.highPriorityGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in onChanged() }
                    .onEnded { _ in onEnded() },
            )
        } else {
            content
        }
    }
}
