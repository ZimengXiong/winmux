import AppKit
import SwiftUI

enum WindowIntentPreviewPalette {
    static let gridBaseFill = Color.accentColor.opacity(0.07)
    static let gridLineStroke = Color.accentColor.opacity(0.48)
    static let gridOuterStroke = Color.accentColor.opacity(0.48)

    static func gridZoneFill(isActive: Bool) -> Color {
        Color.accentColor.opacity(isActive ? 0.23 : 0.045)
    }

    static func gridSymbol(isActive: Bool) -> Color {
        Color.white.opacity(isActive ? 1.0 : 0.7)
    }
}
