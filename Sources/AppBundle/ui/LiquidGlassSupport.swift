import SwiftUI

var usesNativeLiquidGlass: Bool {
    if #available(macOS 26.0, *) {
        true
    } else {
        false
    }
}

@ViewBuilder
func liquidGlassBackground<S: Shape, Fallback: View>(
    in shape: S,
    isInteractive: Bool = true,
    @ViewBuilder fallback: () -> Fallback,
) -> some View {
    if #available(macOS 26.0, *) {
        Color.clear
            .glassEffect(.regular.interactive(isInteractive), in: shape)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    } else {
        fallback()
    }
}
