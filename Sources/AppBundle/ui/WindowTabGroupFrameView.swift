import SwiftUI

struct WindowTabGroupFrameView: View {
    let strip: WindowTabStripViewModel
    let groupSize: CGSize

    var body: some View {
        let tabHeight = min(strip.frame.height, groupSize.height)
        let outerShape = WindowTabGroupOuterShape(activeWindowCornerRadius: strip.activeWindowCornerRadius)
        let shellShape = WindowTabGroupShellShape(
            tabBarHeight: tabHeight,
            activeWindowCornerRadius: strip.activeWindowCornerRadius
        )
        ZStack(alignment: .topLeading) {
            // One continuous glass material across the tab bar AND the frame ring, masked to
            // the shell so the window cutout stays clear — no material seam between the bar
            // and the body.
            GlassSurface(shape: outerShape)
                .mask {
                    shellShape.fill(style: FillStyle(eoFill: true))
                }

            outerShape
                .stroke(Color.white.opacity(GlassToken.borderOpacity), lineWidth: windowTabGroupFrameStrokeWidth)
                .glassShadow(.raised)

            // Hairline between the tab bar and the window content area.
            Rectangle()
                .fill(Color.white.opacity(GlassToken.separatorOpacity))
                .frame(height: StrokeToken.hairline)
                .offset(y: tabHeight - StrokeToken.hairline)

            WindowTabGroupInnerBoundaryShape(
                tabBarHeight: tabHeight,
                activeWindowCornerRadius: strip.activeWindowCornerRadius
            )
                .stroke(mattePanelInsetShadow, lineWidth: windowTabGroupFrameInnerStrokeWidth)
        }
        .frame(width: groupSize.width, height: groupSize.height)
        .allowsHitTesting(false)
    }
}
