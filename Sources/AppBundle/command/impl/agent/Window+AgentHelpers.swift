extension Window {
    @MainActor
    var agentLayoutDescription: String {
        guard let parent else { return "unbound" }
        return switch getChildParentRelation(child: self, parent: parent) {
            case .floatingWindow: "floating"
            case .tiling(let parent): "\(parent.orientation.rawValue)_\(parent.layout.rawValue)"
            case .macosNativeFullscreenWindow: "macos_native_fullscreen"
            case .macosNativeHiddenAppWindow: "macos_native_hidden_app"
            case .macosNativeMinimizedWindow: "macos_native_minimized"
            case .macosPopupWindow: "macos_popup"
            case .rootTilingContainer, .shimContainerRelation: "internal"
        }
    }
}
