import Foundation

@MainActor
var shouldSuppressChromeForNativeFullscreenContent = false

@MainActor
func updateNativeFullscreenChromeSuppression(nativeFocused: Window?) async {
    shouldSuppressChromeForNativeFullscreenContent = (try? await nativeFocused?.isMacosFullscreen) == true
}

@MainActor
func workspaceContainsWinMuxFullscreenContent(_ workspace: Workspace) -> Bool {
    workspace.allLeafWindowsRecursive.contains(where: \.isFullscreen)
}

@MainActor
func shouldSuppressChromeForWinMuxFullscreenContent(on monitor: Monitor) -> Bool {
    workspaceContainsWinMuxFullscreenContent(monitor.activeWorkspace)
}

@MainActor
func shouldSuppressChromeForFullscreenContent(on monitor: Monitor) -> Bool {
    shouldSuppressChromeForNativeFullscreenContent ||
        shouldSuppressChromeForWinMuxFullscreenContent(on: monitor)
}
