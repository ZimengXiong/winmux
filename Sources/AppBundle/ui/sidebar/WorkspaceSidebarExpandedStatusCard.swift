import Foundation
import SwiftUI

struct WorkspaceSidebarExpandedStatusCard: View {
    let date: Date
    let sectionWidth: CGFloat
    let showsSeconds: Bool
    let showsDate: Bool
    let showsWeekday: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .top, spacing: 4) {
                Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.90))
                    .lineLimit(1)
                if showsSeconds {
                    Text(date, format: .dateTime.second(.twoDigits))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.34))
                        .lineLimit(1)
                        .padding(.top, 9)
                }
            }
            .layoutPriority(1)

            if showsDate || showsWeekday {
                VStack(alignment: .leading, spacing: 1) {
                    if showsWeekday {
                        Text(date, format: .dateTime.weekday(.abbreviated))
                    }
                    if showsDate {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                    }
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
                .fill(Color.white.opacity(GlassToken.fillResting))
                .overlay {
                    RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(GlassToken.cardStroke), lineWidth: StrokeToken.hairline)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(workspaceSidebarExpandedClockAccessibilityParts(
            date: date,
            showsSeconds: showsSeconds,
            showsDate: showsDate,
            showsWeekday: showsWeekday,
        ).joined(separator: ", ")))
    }
}

func workspaceSidebarExpandedClockAccessibilityParts(
    date: Date,
    showsSeconds: Bool,
    showsDate: Bool,
    showsWeekday: Bool,
) -> [String] {
    var parts = [date.formatted(date: .omitted, time: showsSeconds ? .standard : .shortened)]
    if showsWeekday {
        parts.append(date.formatted(.dateTime.weekday(.wide)))
    }
    if showsDate {
        parts.append(date.formatted(.dateTime.month(.wide).day()))
    }
    return parts
}
