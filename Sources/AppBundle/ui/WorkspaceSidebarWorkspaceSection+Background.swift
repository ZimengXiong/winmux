import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    var sectionBackground: some View {
        sectionShape
            .fill(sectionBackgroundFill)
            .overlay {
                sectionShape.strokeBorder(sectionBorderColor, lineWidth: sectionBorderWidth)
            }
    }

    var sectionBackgroundFill: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.13)
        }
        if workspace.isFocused {
            return workspaceSidebarActiveWorkspaceTint.opacity(isCompact ? 0.32 : 0.17)
        }
        if isCompact, isHovered {
            return Color.white.opacity(0.06)
        }
        if isHovered {
            return Color.white.opacity(0.045)
        }
        if workspace.isVisible && expansionProgress > 0.5 {
            return Color.white.opacity(0.02)
        }
        return Color.clear
    }

    var sectionBorderColor: Color {
        if isDropTarget { return Color.accentColor.opacity(0.46) }
        if workspace.isFocused { return workspaceSidebarActiveWorkspaceTint.opacity(isCompact ? 0.70 : 0.42) }
        if isHovered || workspace.isVisible { return mattePanelSeparator.opacity(isCompact ? 0.32 : 0.24) }
        return Color.clear
    }

    var sectionBorderWidth: CGFloat {
        if isDropTarget { return 1.5 }
        if workspace.isFocused { return isCompact ? 0.9 : 0.7 }
        if isHovered || workspace.isVisible { return 0.6 }
        return 0.5
    }
}
