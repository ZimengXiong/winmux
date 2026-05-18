import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    var sectionBackground: some View {
        sectionShape
            .fill(sectionBackgroundFill)
    }

    var sectionBackgroundFill: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.12)
        }
        if isInUseOnOtherDisplay {
            return Color(nsColor: .systemRed).opacity(isHovered ? 0.18 : 0.10)
        }
        let activeTint = isFromOtherDisplay ? Color(nsColor: .systemPink) : workspaceSidebarActiveWorkspaceTint
        if workspace.isFocused {
            return activeTint.opacity(isCompact ? 0.24 : 0.12)
        }
        if isFromOtherDisplay {
            return Color(nsColor: .systemPink).opacity(isHovered ? 0.10 : 0.05)
        }
        if isHovered {
            return Color.white.opacity(0.045)
        }
        return Color.white.opacity(0.015)
    }

    var inUseOverrideOverlay: some View {
        WorkspaceSidebarInUseOverrideOverlay(text: inUseOverrideText) {
            activeInUseOverrideWorkspaceName = nil
            actions.send(.selectWorkspace(workspace.name))
        }
    }
}
