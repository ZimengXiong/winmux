import AppKit
import Common
import SwiftUI

// MARK: - Create Workspace Section

struct WorkspaceSidebarCreateWorkspaceSection: View {
    let dragPreview: WorkspaceSidebarDropPreviewViewModel?
    let expansionProgress: CGFloat
    let emitsDropTarget: Bool
    let onCreateWorkspace: () -> Void

    @State private var isHovered = false
    private var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress) }
    private var contentWidth: CGFloat { workspaceSidebarContentWidth(expansionProgress) }
    private var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    private var isDropTarget: Bool { dragPreview?.targetsNewWorkspace == true }
    private var sectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()) else { return }
                onCreateWorkspace()
            } label: {
                Group {
                    if isCompact {
                        plusBadge
                            .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)
                    } else {
                        HStack(spacing: workspaceSidebarHeaderSpacing) {
                            plusBadge
                            Text("New Workspace")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.66))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, workspaceSidebarSectionInnerHorizontalInset)
                .frame(width: sectionWidth, alignment: isCompact ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                .background(
                    sectionShape
                        .fill(createSectionFill)
                        .overlay {
                            sectionShape
                                .strokeBorder(
                                    isDropTarget ? Color.accentColor.opacity(0.46) : Color.white.opacity(isHovered ? 0.06 : 0),
                                    lineWidth: isDropTarget ? 1.5 : 0.5
                                )
                        }
                )
                .contentShape(sectionShape)
                }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
            .contentShape(sectionShape)
            .onHover { hover in
                isHovered = hover
            }
            if dragPreview?.targetsNewWorkspace == true {
                WorkspaceSidebarPreviewRow(
                    preview: dragPreview.orDie(),
                    expansionProgress: expansionProgress,
                    rowHeight: 22,
                    expandedContentWidth: contentWidth
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
                    removal: .opacity,
                ))
            }
        }
        .frame(width: sectionWidth, alignment: isCompact ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
        .clipped()
        .zIndex(isDropTarget ? 1 : 0)
        .shadow(
            color: isDropTarget ? Color.accentColor.opacity(0.18) : .clear,
            radius: isDropTarget ? 12 : 0
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.84), value: dragPreview)
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
    }

    private var createSectionFill: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.13)
        }
        if isHovered {
            return Color.white.opacity(isCompact ? 0.08 : 0.06)
        }
        return Color.clear
    }

    private var plusBadge: some View {
        Image(systemName: "plus")
            .font(.system(size: isCompact ? 10 : 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(isHovered || isDropTarget ? 0.80 : 0.58))
            .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth, alignment: .center)
    }
}
