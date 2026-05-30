import Foundation

@MainActor
var shouldSuppressChromeForNativeFullscreenContent = false

@MainActor
func updateNativeFullscreenChromeSuppression(nativeFocused: Window?) async {
    shouldSuppressChromeForNativeFullscreenContent = (try? await nativeFocused?.isMacosFullscreen) == true
}

@MainActor
func shouldSuppressChromeForFullscreenContent(on monitor: Monitor) -> Bool {
    shouldSuppressChromeForNativeFullscreenContent
}

@MainActor
func shouldSuppressWorkspaceSidebarForFullscreenContent() -> Bool {
    shouldSuppressChromeForNativeFullscreenContent
}
