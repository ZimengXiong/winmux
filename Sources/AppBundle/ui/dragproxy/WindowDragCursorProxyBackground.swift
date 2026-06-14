import SwiftUI

struct WindowDragCursorProxyBackground: View {
    var isGroup: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
            .fill(Color.white.opacity(isGroup ? GlassToken.fillActive : GlassToken.fillHover))
            .overlay {
                RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(GlassToken.strokeHover), lineWidth: StrokeToken.control)
            }
            .glassShadow(.resting)
    }
}
