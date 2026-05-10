import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarProjectPager {
    @ViewBuilder
    func projectDot(
        _ project: WorkspaceSidebarProjectViewModel,
        index: Int,
        swipeProgress: CGFloat,
        edgeProgress: CGFloat,
    ) -> some View {
        let isCurrent = index == currentIndex
        let isSwipeTarget = index == swipeTargetIndex
        let isPressed = pressedProjectId == project.id
        let projectColor = workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex)
        if editingProjectId == project.id && isCompact {
            WorkspaceSidebarProjectRenameField(
                text: $editingProjectDraft,
                focusId: project.id.rawValue,
                alignment: .center,
                fontSize: 11,
                fontWeight: .semibold,
                onCommit: {
                    commitInlineRename(project)
                },
                onCancel: cancelInlineRename,
            )
                .frame(width: 86, height: 24)
                .padding(.horizontal, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.26))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5)
                        }
                )
        } else {
            Button {
                selectWorkspaceSidebarProject(project.id)
            } label: {
                Capsule(style: .continuous)
                    .fill(dotFill(
                        isCurrent: isCurrent,
                        isSwipeTarget: isSwipeTarget,
                        swipeProgress: swipeProgress,
                        edgeProgress: edgeProgress,
                        projectColor: projectColor,
                    ))
                    .frame(
                        width: dotWidth(
                            isCurrent: isCurrent,
                            isSwipeTarget: isSwipeTarget,
                            swipeProgress: swipeProgress,
                            edgeProgress: edgeProgress,
                        ),
                        height: dotHeight(
                            isCurrent: isCurrent,
                            isSwipeTarget: isSwipeTarget,
                            swipeProgress: swipeProgress,
                            edgeProgress: edgeProgress,
                        ),
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(dotBorder(
                                isCurrent: isCurrent,
                                isSwipeTarget: isSwipeTarget,
                                swipeProgress: swipeProgress,
                                edgeProgress: edgeProgress,
                                projectColor: projectColor,
                            ), lineWidth: 0.5)
                    }
                    .scaleEffect(isPressed ? 0.96 : 1)
                    .frame(width: dotHitWidth(
                        isCurrent: isCurrent,
                        isSwipeTarget: isSwipeTarget,
                        swipeProgress: swipeProgress,
                        edgeProgress: edgeProgress,
                    ), height: dotHitHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(project.displayName)
            .help(project.displayName)
            .contextMenu {
                projectContextMenuItems(for: project)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressedProjectId = project.id }
                    .onEnded { _ in pressedProjectId = nil },
            )
            .onTapGesture(count: 2) {
                beginInlineRename(project)
            }
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: swipeProgress)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.84), value: isCurrent)
            .animation(.easeOut(duration: 0.14), value: isPressed)
        }
    }

    func dotSwipeProgress(for index: Int) -> CGFloat {
        let progress = min(max(switchProgress, 0), 1)
        if index == swipeTargetIndex {
            return progress
        }
        if index == currentIndex {
            return swipeTargetIndex == nil && swipeDirection != nil ? 1 : 1 - progress * 0.55
        }
        return 0
    }

    func dotEdgeProgress(for index: Int) -> CGFloat {
        guard index == currentIndex,
              swipeTargetIndex == nil,
              swipeDirection != nil
        else {
            return 0
        }
        return min(max(edgeProgress, 0), 1)
    }

    func dotWidth(isCurrent: Bool, isSwipeTarget: Bool, swipeProgress: CGFloat, edgeProgress: CGFloat) -> CGFloat {
        if isCompact {
            if isCurrent {
                return 18 + 6 * edgeProgress
            }
            if isSwipeTarget {
                return 9 + 9 * swipeProgress
            }
            return 9
        }
        if isCurrent {
            return 18 * max(swipeProgress, 0.45) + 8 * edgeProgress
        }
        if isSwipeTarget {
            return 7 + 15 * swipeProgress
        }
        return 8
    }

    func dotHeight(isCurrent: Bool, isSwipeTarget: Bool, swipeProgress: CGFloat, edgeProgress: CGFloat) -> CGFloat {
        if isCompact {
            return 9
        }
        if isCurrent || isSwipeTarget {
            return 7 + 1.5 * swipeProgress + edgeProgress
        }
        return 7
    }

    func dotHitWidth(isCurrent: Bool, isSwipeTarget: Bool, swipeProgress: CGFloat, edgeProgress: CGFloat) -> CGFloat {
        let visibleWidth = dotWidth(
            isCurrent: isCurrent,
            isSwipeTarget: isSwipeTarget,
            swipeProgress: swipeProgress,
            edgeProgress: edgeProgress,
        )
        if isCompact {
            return max(visibleWidth, 18)
        }
        return max(visibleWidth + 18, 34)
    }

    var dotHitHeight: CGFloat {
        isCompact ? 28 : 34
    }

    func dotFill(
        isCurrent: Bool,
        isSwipeTarget: Bool,
        swipeProgress: CGFloat,
        edgeProgress: CGFloat,
        projectColor: Color,
    ) -> Color {
        if isCompact {
            if isCurrent {
                return projectColor.opacity(0.86 + 0.14 * edgeProgress)
            }
            if isSwipeTarget {
                return projectColor.opacity(0.46 + 0.38 * swipeProgress)
            }
            return projectColor.opacity(isHovered ? 0.58 : 0.42)
        }
        if isCurrent {
            return projectColor.opacity(min(0.42 + 0.42 * max(swipeProgress, 0) + 0.10 * edgeProgress, 1))
        }
        if isSwipeTarget {
            return projectColor.opacity(0.26 + 0.54 * swipeProgress)
        }
        return projectColor.opacity(isHovered ? 0.34 : 0.22)
    }

    func dotBorder(
        isCurrent: Bool,
        isSwipeTarget: Bool,
        swipeProgress: CGFloat,
        edgeProgress: CGFloat,
        projectColor: Color,
    ) -> Color {
        if isCompact {
            if isCurrent || isSwipeTarget {
                return projectColor.opacity(0.95)
            }
            return Color.white.opacity(isHovered ? 0.16 : 0.08)
        }
        if isCurrent || isSwipeTarget {
            return projectColor.opacity(0.55 + 0.18 * swipeProgress + 0.14 * edgeProgress)
        }
        return projectColor.opacity(isHovered ? 0.32 : 0.20)
    }

    func dotShadow(
        isCurrent: Bool,
        isSwipeTarget: Bool,
        swipeProgress: CGFloat,
        edgeProgress: CGFloat,
        projectColor: Color,
    ) -> Color {
        if isCompact {
            if isCurrent || isSwipeTarget {
                return projectColor.opacity(0.18 + 0.12 * max(swipeProgress, edgeProgress))
            }
            return Color.clear
        }
        if isCurrent || isSwipeTarget {
            return projectColor.opacity(0.14 + 0.18 * swipeProgress + 0.12 * edgeProgress)
        }
        return Color.clear
    }
}
