import SwiftUI

struct WorkspaceSidebarStatusMiniIcon: View {
    let symbolName: String
    let tint: Color
    let accessibilityDescription: String

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(tint.opacity(0.92))
            .frame(width: 24, height: 24)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(tint.opacity(0.10), lineWidth: 0.5)
                    }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
    }
}
