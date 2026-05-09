import AppKit
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

struct LiquidGlassSurface<S: Shape>: View {
    let shape: S
    var tint: Color = Color(nsColor: .controlAccentColor)
    var tintOpacity: Double = 0.12
    var scrimOpacity: Double = 0.22
    var highlightOpacity: Double = 0.12
    var borderOpacity: Double = 0.18
    var glowOpacity: Double = 0
    var glowRadius: CGFloat = 0
    var lineWidth: CGFloat = 0.7
    var isInteractive: Bool = true
    var usesEvenOddFill: Bool = false

    var body: some View {
        ZStack {
            liquidGlassBackground(in: shape, isInteractive: isInteractive) {
                shape.fill(.ultraThinMaterial, style: fillStyle)
                    .environment(\.colorScheme, .dark)
            }
            shape
                .fill(Color.black.opacity(scrimOpacity), style: fillStyle)
            shape
                .fill(tint.opacity(tintOpacity), style: fillStyle)
                .blendMode(.overlay)
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(highlightOpacity),
                            Color.white.opacity(highlightOpacity * 0.25),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                    style: fillStyle,
                )
                .blendMode(.screen)
            shape
                .stroke(Color.white.opacity(borderOpacity), lineWidth: lineWidth)
        }
        .compositingGroup()
        .shadow(color: tint.opacity(glowOpacity), radius: glowRadius)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var fillStyle: FillStyle {
        FillStyle(eoFill: usesEvenOddFill)
    }
}
