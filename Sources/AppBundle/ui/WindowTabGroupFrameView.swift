import SwiftUI

struct WindowTabGroupFrameView: View {
    let strip: WindowTabStripViewModel
    let groupSize: CGSize

    var body: some View {
        let tabHeight = min(strip.frame.height, groupSize.height)
        let shellShape = WindowTabGroupShellShape(
            tabBarHeight: tabHeight,
            activeWindowCornerRadius: strip.activeWindowCornerRadius
        )
        let tabBarShape = UnevenRoundedRectangle(
            topLeadingRadius: windowTabStripCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: windowTabStripCornerRadius,
            style: .continuous,
        )
        ZStack(alignment: .topLeading) {
            // The thin ring around the window. Scrim-translucent rather than opaque matte so it
            // reads as the same glass material as the tab bar without paying for a blur pass on
            // a few-pixel-wide band.
            shellShape
                .fill(Color.black.opacity(GlassToken.scrimOpacity), style: FillStyle(eoFill: true))

            shellShape
                .stroke(Color.white.opacity(GlassToken.borderOpacity), lineWidth: windowTabGroupFrameStrokeWidth)
                .glassShadow(.raised)

            // The tab bar: the sidebar's glass surface, clipped to the bar region.
            GlassSurface(shape: tabBarShape)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(GlassToken.separatorOpacity))
                        .frame(height: StrokeToken.hairline)
                }
                .frame(height: tabHeight)

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
