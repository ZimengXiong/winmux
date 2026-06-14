struct WorkspaceViewModel: Hashable {
    let name: String
    let displayName: String
    let suffix: String
    let isFocused: Bool
    let isEffectivelyEmpty: Bool
    let isVisible: Bool
    let hasFullscreenWindows: Bool
}
