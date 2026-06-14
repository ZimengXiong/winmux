import AppKit
import SwiftUI

func workspaceSidebarColor(hex: String) -> Color? {
    guard let nsColor = workspaceSidebarNSColor(hex: hex) else { return nil }
    return Color(nsColor: nsColor)
}

func workspaceSidebarNSColor(hex: String) -> NSColor? {
    guard let normalized = normalizedWorkspaceSidebarColorHex(hex),
          let rgb = UInt32(String(normalized.dropFirst()), radix: 16)
    else { return nil }
    return NSColor(
        srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
        green: CGFloat((rgb >> 8) & 0xff) / 255,
        blue: CGFloat(rgb & 0xff) / 255,
        alpha: 1,
    )
}
