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
    @Binding var activeInUseOverrideWorkspaceName: String?
    let actions: WorkspaceSidebarActions

    @State var isHovered = false
    @State var hoveredWindowId: UInt32? = nil
    @State var hoveredTabGroupId: UInt32? = nil
    @State var isDropTargeted = false
    @State var isDropSettling = false
    @State var isEditingName = false
    @State var editingNameDraft = ""
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let headerHeight: CGFloat = workspaceSidebarWorkspaceSectionHeaderHeight
    let rowHeight: CGFloat = workspaceSidebarWorkspaceRowHeight

    var contentWidth: CGFloat { workspaceSidebarContentWidth(expansionProgress, layout: layout) }
    var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress, layout: layout) }
    var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    var showsWindowRows: Bool { expansionProgress >= workspaceSidebarRowsRevealProgress }
    var isDropTarget: Bool { dragPreview?.targetWorkspaceName == workspace.name }
    var activeSidebarDragSourceWindowId: UInt32? { dragPreview?.sourceWindowId }
    var isShowingInUseOverlay: Bool { activeInUseOverrideWorkspaceName == workspace.name }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .contextMenu {
                Button("Rename Workspace") {
                    beginInlineRename()
                }
                Button("Reset Workspace Name") {
                    actions.send(.resetWorkspace(workspace.name))
                }
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
            .background {
                ZStack {
                    sectionBackground
                if !isCompact && !isInUseOnOtherDisplay {
                    sectionActivationButton
                }
                }
            }
            .overlay(alignment: .center) {
                inUseOverrideOverlay
                    .opacity(isShowingInUseOverlay && !isEditingName ? 1 : 0)
                    .allowsHitTesting(isShowingInUseOverlay && !isEditingName)
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
