import SwiftUI

struct WorkspaceSidebarStatusMiniIcon: View {
    let symbolName: String
    let tint: Color
    let accessibilityDescription: String

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint.opacity(0.75))
            .frame(width: 18, height: 18)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tint.opacity(0.08))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
    }
}
