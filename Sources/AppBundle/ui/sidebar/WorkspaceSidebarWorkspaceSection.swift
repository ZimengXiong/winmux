import AppKit
import Common
import SwiftUI

struct WorkspaceSidebarWorkspaceSection: View {
    let workspace: WorkspaceSidebarWorkspaceViewModel
    let dragPreview: WorkspaceSidebarDropPreviewViewModel?
    let expansionProgress: CGFloat
    let layout: WorkspaceSidebarConfiguration
    let emitsDropTarget: Bool
    let isFromOtherDisplay: Bool
    let isInUseOnOtherDisplay: Bool
    let isOnFocusedMonitor: Bool
    let allowsWorkspaceActivation: Bool
    let isPinnedActiveWorkspace: Bool
    let isActiveOnTargetMonitor: Bool
    let projectContextLabel: String?
    let projectContextColor: Color?
    @Binding var renamingWorkspaceName: String?
    @Binding var renamingWorkspaceText: String
    let onBeginRenameWorkspace: @MainActor () -> Void
    let onCommitRenameWorkspace: @MainActor () -> Void
    let onCancelRenameWorkspace: @MainActor () -> Void
    let selectedSearchTarget: WorkspaceSidebarSearchSelection?
    let isSearchFiltering: Bool
    @Binding var activeInUseOverrideWorkspaceName: String?
    let actions: WorkspaceSidebarActions

    @State var isHovered = false
    @State var hoveredWindowId: UInt32? = nil
    @State var hoveredTabGroupId: UInt32? = nil
    @State var isDropTargeted = false
    @State var isDropSettling = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let headerHeight: CGFloat = workspaceSidebarWorkspaceSectionHeaderHeight
    let rowHeight: CGFloat = workspaceSidebarWorkspaceRowHeight

    var contentWidth: CGFloat { workspaceSidebarContentWidth(expansionProgress, layout: layout) }
    var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress, layout: layout) }
    var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    var showsWindowRows: Bool { expansionProgress >= workspaceSidebarRowsRevealProgress }
    var sectionMinHeight: CGFloat? {
        if !isCompact, allowsWorkspaceActivation, isInUseOnOtherDisplay, workspace.items.isEmpty {
            return workspaceSidebarInUseOverrideEmptySectionMinHeight
        }
        return nil
    }
    var isDropTarget: Bool { dragPreview?.targetWorkspaceName == workspace.name }
    var activeSidebarDragSourceWindowId: UInt32? { dragPreview?.sourceWindowId }
    var isShowingInUseOverlay: Bool { activeInUseOverrideWorkspaceName == workspace.name }
    var isSearchSelectedWorkspace: Bool { selectedSearchTarget == .workspace(workspace.name) }
    var isRenamingWorkspace: Bool { renamingWorkspaceName == workspace.name }
    var inUseOverrideText: String {
        if let monitorName = workspace.monitorName, !monitorName.isEmpty {
            return "In use on \(monitorName)"
        }
        return "In use on another display"
    }
    var sectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }

    var body: some View {
        interactiveSectionContent
            .padding(.vertical, isCompact ? 3 : 4)
            .padding(.horizontal, workspaceSidebarSectionInnerHorizontalInset)
            .frame(width: sectionWidth, alignment: .leading)
            .frame(minHeight: sectionMinHeight, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .opacity(compactFocusOpacity)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    debugWorkspaceSidebarRenameLog("workspaceContextRename workspace=\(workspace.name) displayName=\(workspace.displayName) compact=\(isCompact)")
                    onBeginRenameWorkspace()
                } label: {
                    Text("Rename Workspace")
                }
                Divider()
                Button(role: .destructive) {
                    actions.send(.deleteWorkspace(workspace.name))
                } label: {
                    Text("Delete Workspace")
                }
            }
            .onHover { hover in
                isHovered = hover
                actions.hoverWorkspace(workspace.name, hover)
            }
            .onDrop(of: [workspaceSidebarDragPayloadType], delegate: WorkspaceSidebarDropDelegate(
                target: .workspace(workspace.name),
                actions: actions,
                performPayloadDrop: handlePayloadDrop,
                isTargeted: $isDropTargeted,
                isSettling: $isDropSettling,
            ))
            .help(isInUseOnOtherDisplay ? inUseOverrideText : workspace.displayName)
            .zIndex(isDropTarget ? 1 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: dragPreview)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: expansionProgress)
            .animation(reduceMotion ? workspaceSidebarReducedMotionHoverAnimation : workspaceSidebarHoverAnimation, value: isHovered)
            .animation(reduceMotion ? workspaceSidebarReducedMotionHoverAnimation : workspaceSidebarHoverAnimation, value: hoveredWindowId)
            .animation(reduceMotion ? workspaceSidebarReducedMotionHoverAnimation : workspaceSidebarHoverAnimation, value: hoveredTabGroupId)
            .animation(reduceMotion ? workspaceSidebarReducedMotionHoverAnimation : workspaceSidebarHoverAnimation, value: isOnFocusedMonitor)
            .background {
                ZStack {
                    sectionBackground
                if !isCompact && allowsWorkspaceActivation {
                    sectionActivationButton
                }
                }
            }
            .overlay(alignment: .center) {
                inUseOverrideOverlay
                    .opacity(allowsWorkspaceActivation && isShowingInUseOverlay ? 1 : 0)
                    .allowsHitTesting(allowsWorkspaceActivation && isShowingInUseOverlay)
                    .zIndex(5)
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
}
extension WorkspaceSidebarWorkspaceSection {
    func handleSectionClick() {
        guard allowsWorkspaceActivation else { return }
        if isInUseOnOtherDisplay {
            activeInUseOverrideWorkspaceName = workspace.name
            return
        }
        if shouldHandleWorkspaceSidebarActivation(
            isEditing: false,
            isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()
        ) {
            actions.send(.selectWorkspace(workspace.name))
        }
    }

    func handlePayloadDrop(_ payload: WorkspaceSidebarDragPayload) {
        guard !workspaceSidebarPayload(payload, comesFromWorkspace: workspace.name) else {
            actions.send(.clearDropPreview)
            WindowDragCursorProxyPanel.shared.hide()
            return
        }
        switch payload {
            case .window(let windowId):
                actions.send(.moveWindow(windowId, toWorkspace: workspace.name))
            case .tabGroup(let representativeWindowId):
                actions.send(.moveTabGroup(representativeWindowId, toWorkspace: workspace.name))
        }
    }
}

@MainActor
private func workspaceSidebarPayload(_ payload: WorkspaceSidebarDragPayload, comesFromWorkspace workspaceName: String) -> Bool {
    switch payload {
        case .window(let windowId):
            return Window.get(byId: windowId)?.nodeWorkspace?.name == workspaceName
        case .tabGroup(let representativeWindowId):
            guard let window = Window.get(byId: representativeWindowId) else { return false }
            return dragSubjectNode(for: window, subject: .group).nodeWorkspace?.name == workspaceName
    }
}
extension WorkspaceSidebarWorkspaceSection {
    var sectionBackground: some View {
        sectionShape
            .fill(sectionBackgroundFill)
            .overlay {
                if isPinnedActiveWorkspace && !isSearchFiltering {
                    sectionShape
                        .strokeBorder(
                            Color.white.opacity(0.24),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                }
            }
    }

    var sectionBackgroundFill: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.12)
        }
        if isSearchSelectedWorkspace {
            return Color.white.opacity(0.105)
        }
        if isSearchFiltering {
            return isHovered ? Color.white.opacity(0.045) : Color.white.opacity(0.015)
        }
        if allowsWorkspaceActivation && isInUseOnOtherDisplay {
            let redOpacity: Double = workspace.isFocused ? 0.16 : 0.065
            let hoveredRedOpacity: Double = workspace.isFocused ? 0.24 : 0.13
            return Color(nsColor: .systemRed).opacity(isHovered ? hoveredRedOpacity : redOpacity)
        }
        if isPinnedActiveWorkspace {
            return workspaceSidebarActiveWorkspaceTint.opacity(isHovered ? 0.12 : 0.075)
        }
        let activeTint = isFromOtherDisplay ? Color(nsColor: .systemPink) : workspaceSidebarActiveWorkspaceTint
        if isActiveOnTargetMonitor {
            let compactOpacity: Double = workspace.isFocused ? 0.24 : 0.14
            let expandedOpacity: Double = workspace.isFocused ? 0.12 : 0.07
            return activeTint.opacity(isCompact ? compactOpacity : expandedOpacity)
        }
        if isFromOtherDisplay {
            return Color(nsColor: .systemPink).opacity(isHovered ? 0.10 : 0.05)
        }
        if isHovered {
            return Color.white.opacity(0.045)
        }
        return Color.white.opacity(0.015)
    }

    var compactFocusOpacity: Double {
        isCompact && !isOnFocusedMonitor ? 0.72 : 1
    }

    var inUseOverrideOverlay: some View {
        WorkspaceSidebarInUseOverrideOverlay(text: inUseOverrideText) {
            activeInUseOverrideWorkspaceName = nil
            actions.send(.overrideWorkspaceInUse(workspace.name))
        }
    }
}
extension WorkspaceSidebarWorkspaceSection {
    var workspaceBadge: some View {
        Text(workspaceBadgeText)
            .font(.system(size: 18, weight: isActiveOnTargetMonitor ? .bold : .semibold))
            .monospacedDigit()
            .foregroundStyle(workspaceBadgeForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth)
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
            if !suffix.isEmpty { return suffix }
        }
        return workspace.displayName.first.map { String($0).uppercased() } ?? "W"
    }

    var workspaceBadgeForeground: Color {
        if isActiveOnTargetMonitor {
            return Color.white
        }
        return Color.white.opacity(0.70)
    }
}
extension WorkspaceSidebarWorkspaceSection {
    var headerButton: some View {
        Button(action: handleSectionClick) {
            header
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var header: some View {
        Group {
            if isCompact {
                workspaceBadge
                    .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                expandedHeader
            }
        }
    }

    var expandedHeader: some View {
        HStack(spacing: workspaceSidebarHeaderSpacing) {
            if isRenamingWorkspace {
                WorkspaceSidebarWorkspaceRenameField(
                    text: $renamingWorkspaceText,
                    workspaceName: workspace.name,
                    onCommit: onCommitRenameWorkspace,
                    onCancel: onCancelRenameWorkspace,
                )
            } else {
                Text(workspace.displayName)
                    .font(.system(size: 15, weight: isActiveOnTargetMonitor ? .bold : .semibold))
                    .foregroundStyle(isActiveOnTargetMonitor ? Color.white : Color.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let projectContextLabel, let projectContextColor {
                Text(projectContextLabel)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(projectContextColor.opacity(0.86))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background {
                        Capsule(style: .continuous)
                            .fill(projectContextColor.opacity(0.13))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(projectContextColor.opacity(0.24), lineWidth: 0.5)
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, workspaceSidebarHeaderRowLeadingPadding)
        .padding(.trailing, workspaceSidebarRowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
extension WorkspaceSidebarWorkspaceSection {
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
            WorkspaceSidebarDropPreviewView(preview: dragPreview.orDie(), rowHeight: rowHeight)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
                removal: .identity,
            ))
        }
    }
}
extension WorkspaceSidebarWorkspaceSection {
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
            sectionContent.contentShape(sectionShape)
        }
    }

    var sectionActivationButton: some View {
        Button(action: handleSectionClick) {
            Color.clear.contentShape(sectionShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(workspace.displayName)
    }

    var sectionContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            headerSlot
                .frame(height: headerHeight)
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
            windowRows
            dropPreviewRow
        }
    }

    @ViewBuilder
    var headerSlot: some View {
        header
            .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
    }
}
extension WorkspaceSidebarWorkspaceSection {
    func workspaceTabGroupView(_ group: WorkspaceSidebarTabGroupViewModel) -> some View {
        let isDragging = activeSidebarDragSourceWindowId == group.representativeWindowId
        return VStack(alignment: .leading, spacing: 1) {
            tabGroupHeaderButton(group)
            tabGroupTabs(group, isDragging: isDragging)
        }
        .padding(.vertical, 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: isDragging)
    }

    func tabGroupTabs(_ group: WorkspaceSidebarTabGroupViewModel, isDragging: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(group.searchVisibleTabs ?? group.tabs) { tab in
                workspaceWindowButton(
                    tab,
                    allowsDrag: true,
                    subject: .window,
                    leadingHitInset: workspaceSidebarTabGroupChildLeadingIndent,
                )
            }
        }
        .opacity(1)
    }
}
extension WorkspaceSidebarWorkspaceSection {
    func tabGroupHeaderButton(_ group: WorkspaceSidebarTabGroupViewModel) -> some View {
        Button {
            guard allowsWorkspaceActivation else { return }
            guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
            if isInUseOnOtherDisplay {
                activeInUseOverrideWorkspaceName = workspace.name
                return
            }
            activeInUseOverrideWorkspaceName = nil
            actions.send(.selectWindow(group.representativeWindowId))
        } label: {
            WorkspaceSidebarWindowRow(
                title: group.title.isEmpty ? "Tab Group" : group.title,
                badge: group.windowCount > 1 ? "\(group.windowCount)" : nil,
                isFocused: group.isFocused,
                suppressFocusedStyle: isSearchFiltering,
                rowHeight: rowHeight,
                isHovered: hoveredTabGroupId == group.representativeWindowId || selectedSearchTarget == .window(group.representativeWindowId),
                style: .tabGroupHeader,
                appBundleIds: group.tabs.map(\.appBundleId),
                appBundlePaths: group.tabs.map(\.appBundlePath),
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(WorkspaceSidebarOptionalDragModifier(
            isEnabled: true,
            onChanged: { actions.tabGroupDragChanged(group.representativeWindowId, $0) },
            onEnded: { actions.tabGroupDragEnded(group.representativeWindowId, $0) },
        ))
        .workspaceSidebarDrag(enabled: true) {
            WorkspaceSidebarDragPayload.tabGroup(group.representativeWindowId).itemProvider
        }
        .onHover { hover in
            hoveredTabGroupId = hover ? group.representativeWindowId :
                (hoveredTabGroupId == group.representativeWindowId ? nil : hoveredTabGroupId)
        }
        .opacity(1)
    }
}
extension WorkspaceSidebarWorkspaceSection {
    func workspaceWindowButton(
        _ window: WorkspaceSidebarWindowViewModel,
        allowsDrag: Bool,
        subject: WindowDragSubject = .window,
        leadingHitInset: CGFloat = 0,
    ) -> some View {
        Button {
            guard allowsWorkspaceActivation else { return }
            guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
            if isInUseOnOtherDisplay {
                activeInUseOverrideWorkspaceName = workspace.name
                return
            }
            activeInUseOverrideWorkspaceName = nil
            actions.send(.selectWindow(window.windowId))
        } label: {
            WorkspaceSidebarWindowRow(
                title: window.title ?? window.appName,
                badge: nil,
                isFocused: window.isFocused,
                suppressFocusedStyle: isSearchFiltering,
                rowHeight: rowHeight,
                isHovered: hoveredWindowId == window.windowId || selectedSearchTarget == .window(window.windowId),
                style: leadingHitInset > 0 ? .tabGroupChild : .window,
                appBundleIds: [window.appBundleId],
                appBundlePaths: [window.appBundlePath],
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
            onChanged: { pointer in
                if subject == .group {
                    actions.tabGroupDragChanged(window.windowId, pointer)
                } else {
                    actions.windowDragChanged(window.windowId, pointer)
                }
            },
            onEnded: { pointer in
                if subject == .group {
                    actions.tabGroupDragEnded(window.windowId, pointer)
                } else {
                    actions.windowDragEnded(window.windowId, pointer)
                }
            },
        ))
        .workspaceSidebarDrag(enabled: allowsDrag) {
            WorkspaceSidebarDragPayload.window(window.windowId).itemProvider
        }
        .onHover { hover in
            hoveredWindowId = nextWorkspaceSidebarHoveredWindowId(
                currentHoveredWindowId: hoveredWindowId,
                windowId: window.windowId,
                isHovering: hover,
            )
        }
        .opacity(1)
        .animation(.spring(response: 0.2, dampingFraction: 0.78), value: activeSidebarDragSourceWindowId == window.windowId)
    }
}
