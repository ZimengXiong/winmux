import SwiftUI

struct WindowDragCursorProxyBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(mattePanelFill)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(mattePanelSeparator, lineWidth: 0.7)
            }
            .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
    }
}
