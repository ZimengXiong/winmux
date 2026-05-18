import SwiftUI

extension WindowTabItemView {
    var feedbackId: String {
        isHovered ? "hover-pill" : "active-pill-\(tab.windowId)"
    }

    var baseTabFill: Color {
        tab.isActive ? Color.white.opacity(0.16) : Color.white.opacity(0.06)
    }

    var feedbackFill: Color {
        if isHovered {
            return Color.white.opacity(tab.isActive ? 0.08 : 0.04)
        }
        return Color.clear
    }

    var feedbackOpacity: Double {
        isHovered || tab.isActive ? 1 : 0
    }

    var foregroundColor: Color {
        if tab.isActive { return Color.white.opacity(0.95) }
        if isDragSource { return Color.white.opacity(0.80) }
        return isHovered ? Color.white.opacity(0.78) : Color.white.opacity(0.68)
    }
}
