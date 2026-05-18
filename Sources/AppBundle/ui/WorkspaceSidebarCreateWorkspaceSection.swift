import AppKit
import Common
import SwiftUI

// MARK: - Create Workspace Section

struct WorkspaceSidebarCreateWorkspaceSection: View {
    let dragPreview: WorkspaceSidebarDropPreviewViewModel?
    let expansionProgress: CGFloat
    let layout: WorkspaceSidebarConfiguration
    let emitsDropTarget: Bool
    let onCreateWorkspace: () -> Void
    let onDropPayload: @MainActor (WorkspaceSidebarDragPayload) -> Void
    let actions: WorkspaceSidebarActions

    @State private var isDropTargeted = false
    @State private var isDropSettling = false

    private var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress, layout: layout) }
    private var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    private var showsDropTarget: Bool { dragPreview?.targetsNewWorkspace == true }
    private var sectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsDropTarget, let dragPreview {
                WorkspaceSidebarDropPreviewView(
                    preview: dragPreview,
                    rowHeight: workspaceSidebarWorkspaceRowHeight,
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
                    removal: .opacity,
                ))
            } else {
                createButton
            }
        }
        .frame(width: sectionWidth, alignment: isCompact ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
        .clipped()
        .zIndex(showsDropTarget ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showsDropTarget)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: WorkspaceSidebarDropTargetPreferenceKey.self,
                    value: emitsDropTarget ? [WorkspaceSidebarDropTargetFrame(
                        kind: .newWorkspace,
                        frame: geometry.frame(in: .named("workspaceSidebarContent")),
                    )] : [],
                )
            }
        }
        .onDrop(of: [workspaceSidebarDragPayloadType], delegate: WorkspaceSidebarDropDelegate(
            target: .newWorkspace,
            actions: actions,
            performPayloadDrop: onDropPayload,
            isTargeted: $isDropTargeted,
            isSettling: $isDropSettling,
        ))
    }

    private var createButton: some View {
        Button {
            guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
            onCreateWorkspace()
        } label: {
            HStack(spacing: workspaceSidebarHeaderSpacing) {
                if isCompact {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.45))
                        Text("New Workspace")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.48))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.vertical, isCompact ? 3 : 4)
            .padding(.horizontal, workspaceSidebarSectionInnerHorizontalInset + workspaceSidebarHeaderRowLeadingPadding)
            .frame(
                width: sectionWidth,
                height: isCompact ? workspaceSidebarWorkspaceSectionHeightCompact : workspaceSidebarWorkspaceSectionHeightExpanded,
                alignment: isCompact ? .center : .leading,
            )
            .background {
                sectionShape.fill(Color.white.opacity(0.012))
            }
            .overlay {
                sectionShape.strokeBorder(
                    Color.white.opacity(0.10),
                    style: StrokeStyle(lineWidth: 0.5, dash: [3, 2.5])
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
