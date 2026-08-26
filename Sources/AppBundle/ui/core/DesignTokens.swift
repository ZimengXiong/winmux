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
    // Width of the refractive Liquid Glass edge band (macOS 26). Wider = more visible
    // refraction; the main knob for how pronounced the glassy border reads.
    static let refractiveBorderWidth: CGFloat = 3

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

extension ChromeSolidColor {
    var color: Color {
        let components = rgb
        return Color(red: components.red, green: components.green, blue: components.blue)
    }
}

extension WorkspaceSidebarConfig {
    var resolvedSolidChromeColor: Color {
        solidChromeColor == .custom ? Color(chromeHex: solidChromeCustomColor) : solidChromeColor.color
    }
}

extension WorkspaceSidebarConfiguration {
    var resolvedSolidChromeColor: Color {
        solidChromeColor == .custom ? Color(chromeHex: solidChromeCustomColor) : solidChromeColor.color
    }
}

extension Color {
    init(chromeHex: String) {
        let hex = chromeHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(hex, radix: 16) ?? 0x191B20
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
        )
    }

    var chromeHex: String {
        let components = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((components.redComponent * 255).rounded()), Int((components.greenComponent * 255).rounded()), Int((components.blueComponent * 255).rounded()))
    }
}

/// The shared glass surface: glass/blur base, dark scrim, neutral tint, top highlight,
/// hairline border.
struct GlassSurface<S: Shape>: View {
    let shape: S
    var hasHighlight: Bool = true
    var hasBorder: Bool = true
    var style: ChromeStyle = .liquidGlass
    var solidColor: Color = .black

    var body: some View {
        ZStack {
            base
            if style == .liquidGlass {
                shape.fill(Color.black.opacity(GlassToken.scrimOpacity))
                shape.fill(GlassToken.tint.opacity(GlassToken.tintOpacity))
                    .blendMode(.plusLighter)
            }
            if hasHighlight, style == .liquidGlass {
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
            if hasBorder {
                borderEdge
            }
        }
        .compositingGroup()
        // `glassEffect` is backed by a rectangular AppKit layer. Clip the composed result,
        // not only its SwiftUI fills, so that backing layer cannot show beyond a shaped edge.
        .clipShape(shape)
    }

    @ViewBuilder
    private var base: some View {
        switch style {
        case .solid:
            shape.fill(solidColor)
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular.interactive(false), in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
        }
    }

    /// The outer edge. On macOS 26 it's a ring of real Liquid Glass masked to just the
    /// border band, so the edge refracts — light bends along the rounded corner like the
    /// native material — over a faint hairline that keeps the outline defined. Older systems
    /// get the plain hairline.
    @ViewBuilder
    private var borderEdge: some View {
        if #available(macOS 26.0, *), style == .liquidGlass {
            Color.clear
                .glassEffect(.regular, in: shape)
                .mask(shape.stroke(lineWidth: GlassToken.refractiveBorderWidth))
                .overlay(shape.stroke(Color.white.opacity(GlassToken.borderOpacity), lineWidth: StrokeToken.hairline))
        } else {
            shape.stroke(Color.white.opacity(GlassToken.borderOpacity), lineWidth: StrokeToken.hairline)
        }
    }
}
