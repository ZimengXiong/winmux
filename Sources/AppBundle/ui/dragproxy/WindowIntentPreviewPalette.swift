import AppKit
import SwiftUI

enum WindowIntentPreviewPalette {
    static func activeZoneFill(style: ChromeStyle, solidColor: Color) -> Color {
        switch style {
            case .liquidGlass:
                Color.white.opacity(GlassToken.fillActive)
            case .solid:
                solidColor.opacity(0.68)
        }
    }

    static func activeZoneStroke(style: ChromeStyle, solidColor: Color) -> Color {
        switch style {
            case .liquidGlass:
                Color.white.opacity(GlassToken.strokeActive)
            case .solid:
                solidColor.opacity(0.96)
        }
    }

    static func activeZoneGlow(style: ChromeStyle, solidColor: Color) -> Color {
        switch style {
            case .liquidGlass:
                Color.white.opacity(0.14)
            case .solid:
                solidColor.opacity(0.34)
        }
    }

    static func zoneSymbol(isActive: Bool) -> Color {
        Color.white.opacity(isActive ? 1.0 : GlassToken.textTertiary)
    }
}
