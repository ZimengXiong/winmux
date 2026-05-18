import AppKit
import SwiftUI

enum WindowIntentPreviewPalette {
    static let fillColor = mattePanelNSColor
    static let fill = Color(nsColor: fillColor)

    static func highlight(style: WindowTabDropPreviewStyle, isActive: Bool) -> Color {
        Color.white.opacity(style.highlightOpacity * (isActive ? 1 : 0.45))
    }

    static func stroke(style: WindowTabDropPreviewStyle, isActive: Bool) -> Color {
        Color(nsColor: fillColor).opacity(style.strokeOpacity * (isActive ? 1 : 0.55))
    }

    static func guide(style: WindowTabDropPreviewStyle, isActive: Bool) -> Color {
        Color(nsColor: fillColor).opacity(style.guideOpacity * (isActive ? 1 : 0.55))
    }

    static func accent(alpha _: CGFloat) -> CGColor {
        fillColor.cgColor
    }
}

private extension WindowTabDropPreviewStyle {
    var highlightOpacity: Double {
        switch self {
            case .swap:
                0.012
            case .detach, .workspaceMove, .sidebarWorkspaceMove:
                0.014
            case .tabInsert, .stackSplit:
                0.016
        }
    }

    var strokeOpacity: Double {
        switch self {
            case .tabInsert, .stackSplit:
                0.38
            case .swap:
                0.34
            case .detach, .workspaceMove, .sidebarWorkspaceMove:
                0.32
        }
    }

    var guideOpacity: Double {
        switch self {
            case .swap:
                0
            case .detach, .workspaceMove, .sidebarWorkspaceMove:
                0.28
            case .tabInsert:
                0.34
            case .stackSplit:
                0.36
        }
    }
}
