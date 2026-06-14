import AppKit

enum ResizePreviewPalette {
    static let fill = mattePanelNSColor.cgColor
    static let stroke = NSColor.white.withAlphaComponent(0.04).cgColor
    static let tabGroupBar = NSColor.white.withAlphaComponent(0.055).cgColor
    static let fallbackIconFill = NSColor.white.withAlphaComponent(0.12).cgColor
    static let sourceFrameFill = mattePanelNSColor.cgColor
    static let sourceFrameStroke = NSColor.white.withAlphaComponent(0.055).cgColor
    static let sourceMockTabFill = NSColor.white.withAlphaComponent(0.085).cgColor
    static let sourceMockTabStroke = NSColor.white.withAlphaComponent(0.075).cgColor
}
