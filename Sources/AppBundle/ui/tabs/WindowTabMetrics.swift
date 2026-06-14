import AppKit

private let windowTabGroupShellHorizontalInsetValue: CGFloat = 3
private let windowTabGroupShellTopInsetValue: CGFloat = 0
private let windowTabGroupShellBottomInsetValue: CGFloat = 3
private let windowTabBarMinimumHeightValue: CGFloat = 36

func windowTabGroupShellHorizontalInset() -> CGFloat {
    windowTabGroupShellHorizontalInsetValue
}

func windowTabGroupShellTopInset() -> CGFloat {
    windowTabGroupShellTopInsetValue
}

func windowTabGroupShellBottomInset() -> CGFloat {
    windowTabGroupShellBottomInsetValue
}

@MainActor
func resolvedWindowTabBarHeight() -> CGFloat {
    max(CGFloat(config.windowTabs.height), windowTabBarMinimumHeightValue)
}
