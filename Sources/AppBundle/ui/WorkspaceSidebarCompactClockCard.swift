import Foundation
import SwiftUI

struct WorkspaceSidebarCompactClockCard: View {
    let date: Date
    let sectionWidth: CGFloat

    private var components: WorkspaceSidebarClockComponents {
        WorkspaceSidebarClockComponents(date: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(components.hour)
                .foregroundStyle(Color.white.opacity(0.88))

            Text(components.minute)
                .foregroundStyle(Color.white.opacity(0.88))

            Text(components.second)
                .foregroundStyle(Color.white.opacity(0.48))
        }
        .font(.system(size: 18, weight: .bold, design: .rounded))
        .monospacedDigit()
        .padding(.leading, 7)
        .frame(width: sectionWidth, alignment: .leading)
        .frame(minHeight: 78)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.075),
                            Color.white.opacity(0.035),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing,
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.hour().minute().second()))
    }
}
