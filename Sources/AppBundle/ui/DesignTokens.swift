import SwiftUI

// WinMux design tokens: the single source of truth for the app's visual language — a dark
// macOS-glass surface (glass/blur base + dark scrim + neutral tint + top highlight + hairline
// border) with one shared scale of radii, strokes, shadows, and motion. Every piece of chrome
// should pull from here so all surfaces read as the same material. The glass recipe is pure
// opacity layers over a single base, so it stays cheap to composite.

enum GlassToken {
    // Surface recipe (originally the sidebar surface, now shared by all chrome)
    static let tint = Color(hue: 0, saturation: 0, brightness: 0.50)
    static let tintOpacity: Double = 0.06
    static let scrimOpacity: Double = 0.58
    static let highlightPeak: Double = 0.08
    static let borderOpacity: Double = 0.10
    static let separatorOpacity: Double = 0.07

    // Interactive fills layered on glass
    static let fillActive: Double = 0.14
    static let fillHover: Double = 0.085
    static let fillResting: Double = 0.06
    static let fillFaint: Double = 0.04

    // Strokes around interactive elements
    static let strokeActive: Double = 0.18
    static let strokeHover: Double = 0.10
    static let strokeResting: Double = 0.06
    static let cardStroke: Double = 0.08

    // Text emphasis on glass
    static let textPrimary: Double = 0.92
    static let textSecondary: Double = 0.74
    static let textTertiary: Double = 0.58
    static let textQuaternary: Double = 0.48
}

enum RadiusToken {
    static let row: CGFloat = 8 // rows, drag proxies, small chips
    static let card: CGFloat = 10 // status cards, dropdown menus
    static let section: CGFloat = 12 // sidebar sections, tab strip, alert panels
    static let panel: CGFloat = 14 // panel outer edges
}

enum StrokeToken {
    static let hairline: CGFloat = 0.5
    static let control: CGFloat = 0.75
    static let emphasis: CGFloat = 1.0
}

struct ShadowToken {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat

    static let resting = ShadowToken(opacity: 0.15, radius: 6, y: 2)
    static let raised = ShadowToken(opacity: 0.18, radius: 8, y: 4)
    static let hover = ShadowToken(opacity: 0.35, radius: 12, y: 6)
}

enum MotionToken {
    static let hover = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.06)
    static let pill = Animation.spring(response: 0.28, dampingFraction: 0.72, blendDuration: 0.08)
    static let appear = Animation.spring(response: 0.30, dampingFraction: 0.85)
    static let quick = Animation.easeOut(duration: 0.12)
}

extension View {
    func glassShadow(_ token: ShadowToken) -> some View {
        shadow(color: Color.black.opacity(token.opacity), radius: token.radius, x: 0, y: token.y)
    }
}

/// The top sheen that makes a surface read as lit glass. Overlay on opaque surfaces (like the
/// tab bar) that can't afford a real blur base but should match the glass language.
struct GlassHighlight: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(GlassToken.highlightPeak), location: 0),
                .init(color: Color.white.opacity(GlassToken.highlightPeak * 0.25), location: 0.12),
                .init(color: Color.clear, location: 0.45),
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

/// The shared glass surface: glass/blur base, dark scrim, neutral tint, top highlight,
/// hairline border.
struct GlassSurface<S: Shape>: View {
    let shape: S
    var hasHighlight: Bool = true

    var body: some View {
        ZStack {
            base
            shape.fill(Color.black.opacity(GlassToken.scrimOpacity))
            shape.fill(GlassToken.tint.opacity(GlassToken.tintOpacity))
                .blendMode(.plusLighter)
            if hasHighlight {
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(GlassToken.highlightPeak), location: 0),
                            .init(color: Color.white.opacity(GlassToken.highlightPeak * 0.25), location: 0.12),
                            .init(color: Color.clear, location: 0.45),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    )
                )
                .blendMode(.screen)
            }
            shape.stroke(Color.white.opacity(GlassToken.borderOpacity), lineWidth: StrokeToken.hairline)
        }
        .compositingGroup()
    }

    @ViewBuilder
    private var base: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.interactive(false), in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
    }
}
