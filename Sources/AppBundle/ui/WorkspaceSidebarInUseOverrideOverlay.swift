import SwiftUI

struct WorkspaceSidebarInUseOverrideOverlay: View {
    let text: String
    let onOverride: () -> Void
    @State private var isOverrideHovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)
                .overlay {
                    shape.fill(Color(nsColor: .systemRed).opacity(0.14))
                }
                .clipShape(shape)

            shape.strokeBorder(Color(nsColor: .systemRed).opacity(0.45), lineWidth: 0.8)

            VStack(spacing: 7) {
                Text(text)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                Button(action: onOverride) {
                    Text("Override")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(nsColor: .systemRed).opacity(isOverrideHovered ? 1 : 0.88))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(isOverrideHovered ? 0.28 : 0), lineWidth: 0.6)
                }
                .onHover { hovering in
                    isOverrideHovered = hovering
                }
            }
        }
        .contentShape(Rectangle())
    }
}
