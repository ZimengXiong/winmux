import SwiftUI

struct WindowDragCursorProxyBackground: View {
    var isGroup: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
            .fill(isGroup ? Color.white.opacity(0.14) : Color.white.opacity(0.085))
            .overlay {
                RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
    }
}
