import SwiftUI

struct WorkspaceSidebarStatusCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
            .fill(Color(hue: 0.61, saturation: 0.18, brightness: 0.13, opacity: 0.55))
            .overlay {
                RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                    .strokeBorder(Color(hue: 0.61, saturation: 0.25, brightness: 0.40, opacity: 0.14), lineWidth: 0.5)
            }
    }
}
