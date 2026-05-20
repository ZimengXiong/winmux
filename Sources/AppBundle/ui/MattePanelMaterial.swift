import AppKit
import SwiftUI

private let mattePanelRed: CGFloat = 0.105
private let mattePanelGreen: CGFloat = 0.105
private let mattePanelBlue: CGFloat = 0.105
private let mattePanelAlpha: CGFloat = 0.96
private let mattePanelSeparatorAlpha: CGFloat = 0.07

let mattePanelNSColor = NSColor(
    calibratedRed: mattePanelRed,
    green: mattePanelGreen,
    blue: mattePanelBlue,
    alpha: mattePanelAlpha,
)
let mattePanelFill = Color(nsColor: mattePanelNSColor)
let mattePanelBorder = Color(nsColor: mattePanelNSColor)
let mattePanelInsetShadow = Color.black.opacity(0.28)
let mattePanelSeparatorNSColor = NSColor.white.withAlphaComponent(mattePanelSeparatorAlpha)
let mattePanelSeparator = Color(nsColor: mattePanelSeparatorNSColor)
