import SwiftUI

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
