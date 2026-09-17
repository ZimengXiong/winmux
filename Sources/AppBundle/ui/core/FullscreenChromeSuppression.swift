import CoreGraphics
import Foundation

@MainActor
var shouldSuppressChromeForNativeFullscreenContent = false

@MainActor
func updateNativeFullscreenChromeSuppression() {
    shouldSuppressChromeForNativeFullscreenContent = isNativeFullscreenWindowOnScreen()
}

/// A natively fullscreen window keeps covering its display no matter what is focused: the
/// frontmost app can live on another Space (an all-spaces panel, a cmd-tab, a CLI command) while
/// the fullscreen video still fills the screen underneath. Deriving the suppression from the
/// focused window therefore put the sidebar back on top of the video the moment focus moved off
/// the fullscreen window -- and it never moved back on its own, so it stayed there.
///
/// Ask the window server what is actually displayed instead: `.optionOnScreenOnly` lists only
/// windows belonging to the Spaces currently on screen, so a fullscreen window shows up exactly
/// while its Space is the one being displayed.
@MainActor
private func isNativeFullscreenWindowOnScreen() -> Bool {
    let fullscreenWindowIds = Set(
        Workspace.all
            .compactMap(\.existingMacOsNativeFullscreenWindowsContainer)
            .flatMap { $0.children.filterIsInstance(of: Window.self) }
            .map(\.windowId)
    )
    // Nothing is natively fullscreen, so skip the CGWindowList snapshot entirely. This is the
    // common case and it runs once per refresh session.
    guard !fullscreenWindowIds.isEmpty else { return false }

    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    guard let windowInfos = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]] else { return false }
    return windowInfos.contains { dict in
        guard let rawWindowId = dict[kCGWindowNumber as String] as? NSNumber else { return false }
        return fullscreenWindowIds.contains(rawWindowId.uint32Value)
    }
}

@MainActor
func shouldSuppressChromeForFullscreenContent(on monitor: Monitor) -> Bool {
    shouldSuppressChromeForNativeFullscreenContent
}

@MainActor
func shouldSuppressWorkspaceSidebarForFullscreenContent() -> Bool {
    shouldSuppressChromeForNativeFullscreenContent
}
