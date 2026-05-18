import SwiftUI

struct WindowTabGroupFrameView: View {
    let strip: WindowTabStripViewModel
    let groupSize: CGSize
    let drawsMockTabs: Bool

    var body: some View {
        let metrics = WindowTabGroupFrameMetrics(strip: strip, groupSize: groupSize)
        ZStack(alignment: .topLeading) {
            WindowTabGroupShellShape(
                outerRadii: metrics.outerRadii,
                innerRect: metrics.innerFrame,
                innerRadii: metrics.innerRadii
            )
            .fill(mattePanelFill, style: FillStyle(eoFill: true))

            WindowTabGroupCornerShieldShape(
                innerRect: metrics.innerFrame,
                topRadius: windowTabGroupTopCornerShieldRadius(metrics.topInnerCornerRadius),
                bottomRadius: windowTabGroupBottomCornerShieldRadius(metrics.appCornerRadius)
            )
            .fill(mattePanelFill, style: FillStyle(eoFill: true))

            if drawsMockTabs {
                WindowTabGroupMockTabsView(
                    strip: strip,
                    stripWidth: groupSize.width,
                    stripHeight: metrics.tabHeight,
                )
                .frame(width: groupSize.width, height: metrics.tabHeight, alignment: .topLeading)
            }

            metrics.outerShape
                .strokeBorder(mattePanelBorder, lineWidth: windowTabGroupFrameStrokeWidth)

            WindowTabDropOutlineShape(cornerRadii: metrics.innerRadii)
                .strokeBorder(mattePanelInsetShadow, lineWidth: windowTabGroupFrameInnerStrokeWidth)
                .frame(width: metrics.innerFrame.width, height: metrics.innerFrame.height)
                .offset(x: metrics.innerFrame.minX, y: metrics.innerFrame.minY)
        }
        .frame(width: groupSize.width, height: groupSize.height)
        .shadow(color: Color.black.opacity(0.10), radius: 6, y: 2)
        .allowsHitTesting(false)
    }
}
