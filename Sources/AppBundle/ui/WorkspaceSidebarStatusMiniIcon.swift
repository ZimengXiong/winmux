import SwiftUI

struct WorkspaceSidebarStatusMiniIcon: View {
    let symbolName: String
    let tint: Color
    let accessibilityDescription: String

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint.opacity(0.65))
            .frame(width: 18, height: 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
    }
}
