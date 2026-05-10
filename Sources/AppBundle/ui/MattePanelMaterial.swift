import AppKit
import SwiftUI

private let mattePanelRed: CGFloat = 0.115
private let mattePanelGreen: CGFloat = 0.115
private let mattePanelBlue: CGFloat = 0.115
private let mattePanelAlpha: CGFloat = 0.94
private let mattePanelSeparatorAlpha: CGFloat = 0.055

let mattePanelNSColor = NSColor(
    calibratedRed: mattePanelRed,
    green: mattePanelGreen,
    blue: mattePanelBlue,
    alpha: mattePanelAlpha,
)
let mattePanelFill = Color(nsColor: mattePanelNSColor)
let mattePanelBorder = Color(nsColor: mattePanelNSColor)
let mattePanelInsetShadow = Color.black.opacity(0.36)
let mattePanelSeparatorNSColor = NSColor.white.withAlphaComponent(mattePanelSeparatorAlpha)
let mattePanelSeparator = Color(nsColor: mattePanelSeparatorNSColor)
