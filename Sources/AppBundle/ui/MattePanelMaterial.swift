import AppKit
import SwiftUI

private let mattePanelRed: CGFloat = 0.075
private let mattePanelGreen: CGFloat = 0.078
private let mattePanelBlue: CGFloat = 0.082
private let mattePanelAlpha: CGFloat = 0.96

let mattePanelNSColor = NSColor(
    calibratedRed: mattePanelRed,
    green: mattePanelGreen,
    blue: mattePanelBlue,
    alpha: mattePanelAlpha,
)
let mattePanelFill = Color(nsColor: mattePanelNSColor)
let mattePanelBorder = Color(nsColor: mattePanelNSColor)
let mattePanelInsetShadow = Color.black.opacity(0.36)
let mattePanelSeparator = Color.white.opacity(0.12)
