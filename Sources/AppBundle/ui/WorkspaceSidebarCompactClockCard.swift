import Foundation
import SwiftUI

struct WorkspaceSidebarCompactClockCard: View {
    let date: Date
    let sectionWidth: CGFloat

    private var components: WorkspaceSidebarClockComponents {
        WorkspaceSidebarClockComponents(date: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(components.hour)
                .foregroundStyle(Color.white.opacity(0.86))

            Text(components.minute)
                .foregroundStyle(Color.white.opacity(0.86))

            Text(components.second)
                .foregroundStyle(Color.white.opacity(0.62))
        }
        .font(.system(size: 18, weight: .semibold))
        .monospacedDigit()
        .padding(.leading, 7)
        .frame(width: sectionWidth, alignment: .leading)
        .frame(minHeight: 84)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.hour().minute().second()))
    }
}
