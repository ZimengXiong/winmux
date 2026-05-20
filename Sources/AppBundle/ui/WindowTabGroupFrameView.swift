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
                .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 6)

            Rectangle()
                .fill(mattePanelFill)
                .frame(height: tabHeight)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(height: 1)
                }
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: windowTabStripCornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: windowTabStripCornerRadius,
                    style: .continuous,
                ))

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
