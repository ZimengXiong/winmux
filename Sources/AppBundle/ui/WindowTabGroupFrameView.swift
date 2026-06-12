import SwiftUI

struct WindowTabGroupFrameView: View {
    let strip: WindowTabStripViewModel
    let groupSize: CGSize

    var body: some View {
        let tabHeight = min(strip.frame.height, groupSize.height)
        ZStack(alignment: .topLeading) {
            WindowTabGroupShellShape(
                tabBarHeight: tabHeight,
                activeWindowCornerRadius: strip.activeWindowCornerRadius
            )
            .fill(mattePanelFill, style: FillStyle(eoFill: true))

            WindowTabGroupShellShape(
                tabBarHeight: tabHeight,
                activeWindowCornerRadius: strip.activeWindowCornerRadius
            )
                .stroke(mattePanelFill, lineWidth: windowTabGroupFrameStrokeWidth)
                .glassShadow(.raised)

            let tabBarShape = UnevenRoundedRectangle(
                topLeadingRadius: windowTabStripCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: windowTabStripCornerRadius,
                style: .continuous,
            )
            Rectangle()
                .fill(mattePanelFill)
                .overlay { GlassHighlight() }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(GlassToken.borderOpacity))
                        .frame(height: StrokeToken.hairline)
                }
                .frame(height: tabHeight)
                .clipShape(tabBarShape)
                .overlay {
                    tabBarShape
                        .stroke(Color.white.opacity(GlassToken.borderOpacity), lineWidth: StrokeToken.hairline)
                        .frame(height: tabHeight)
                }

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
