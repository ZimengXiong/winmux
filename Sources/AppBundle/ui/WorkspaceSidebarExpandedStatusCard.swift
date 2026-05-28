import Foundation
import SwiftUI

struct WorkspaceSidebarExpandedStatusCard: View {
    let date: Date
    let sectionWidth: CGFloat
    let showsDate: Bool

    private var accessibilitySummary: String {
        var parts = [date.formatted(date: .omitted, time: .standard)]
        if showsDate {
            parts.append(date.formatted(date: .complete, time: .omitted))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .top, spacing: 4) {
                Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.90))
                    .lineLimit(1)
                Text(date, format: .dateTime.second(.twoDigits))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.34))
                    .lineLimit(1)
                    .padding(.top, 9)
            }
            .layoutPriority(1)

            if showsDate {
                VStack(alignment: .leading, spacing: 1) {
                    Text(date, format: .dateTime.weekday(.abbreviated))
                    Text(date, format: .dateTime.month(.abbreviated).day())
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.48))
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: sectionWidth, height: 68, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
    }
}
