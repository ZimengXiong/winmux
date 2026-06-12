import SwiftUI

struct WorkspaceSidebarStatusCardBackground: View {
    var body: some View {
        // Neutral card matching the shared glass language (the old blue-tinted HSB fill read as
        // a different material than every other card).
        RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
            .fill(Color.white.opacity(GlassToken.fillResting))
            .overlay {
                RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(GlassToken.cardStroke), lineWidth: StrokeToken.hairline)
            }
    }
}
