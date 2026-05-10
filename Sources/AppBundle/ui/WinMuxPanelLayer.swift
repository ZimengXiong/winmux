import AppKit

enum WinMuxPanelLayer: CaseIterable {
    case windowChrome
    case windowIntentPreview
    case overlay
    case dragCursorProxy
    case workspaceSidebar

    var level: NSWindow.Level {
        switch self {
            case .windowChrome:
                .normal
            case .windowIntentPreview:
                .floating
            case .overlay:
                .statusBar
            case .dragCursorProxy:
                NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            case .workspaceSidebar:
                NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        }
    }
}

extension NSPanelHud {
    func applyWinMuxLayer(_ layer: WinMuxPanelLayer) {
        level = layer.level
    }
}
