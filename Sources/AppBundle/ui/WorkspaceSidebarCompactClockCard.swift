import Foundation
import SwiftUI

struct WorkspaceSidebarCompactClockCard: View {
    let date: Date
    let sectionWidth: CGFloat

    private var components: WorkspaceSidebarClockComponents {
        WorkspaceSidebarClockComponents(date: date)
    }

    var body: some View {
        GeometryReader { _ in
            let shape = RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
            ZStack(alignment: .bottomLeading) {
                shape
                    .fill(Color.white.opacity(0.06))

                VStack(alignment: .center, spacing: 4) {
                    Text(components.hour)
                        .foregroundStyle(Color.white.opacity(0.90))

                    Text(components.minute)
                        .foregroundStyle(Color.white.opacity(0.90))

                    Text(components.second)
                        .foregroundStyle(Color.white.opacity(0.66))
                }
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                shape
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)
            }
            .clipShape(shape)
        }
        .frame(width: sectionWidth, alignment: .leading)
        .frame(height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.hour().minute().second()))
    }
}
