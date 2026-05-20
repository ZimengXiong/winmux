import Foundation
import SwiftUI

struct WorkspaceSidebarExpandedStatusCard: View {
    let date: Date
    let systemStatus: WorkspaceSidebarSystemStatusSnapshot
    let sectionWidth: CGFloat
    let showsDate: Bool
    let showsStatusPills: Bool

    private var effectiveShowsDate: Bool {
        workspaceSidebarExpandedStatusShowsDate(sectionWidth: sectionWidth, configured: showsDate)
    }

    private var effectiveShowsStatusPills: Bool {
        workspaceSidebarExpandedStatusShowsPills(sectionWidth: sectionWidth, configured: showsStatusPills)
    }

    private var accessibilitySummary: String {
        var parts = [date.formatted(date: .omitted, time: .standard)]
        if effectiveShowsDate {
            parts.append(date.formatted(date: .complete, time: .omitted))
        }
        if effectiveShowsStatusPills {
            parts.append(systemStatus.battery.accessibilityDescription)
            parts.append(systemStatus.audio.accessibilityDescription)
            parts.append(systemStatus.network.accessibilityDescription)
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(date, format: .dateTime.second(.twoDigits))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.40))
                    .lineLimit(1)
                    .baselineOffset(3)
            }
            if effectiveShowsDate {
                Text(date, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.leading, 12)
            }
            Spacer(minLength: 0)
            if effectiveShowsStatusPills {
                HStack(alignment: .center, spacing: 7) {
                    WorkspaceSidebarStatusMiniIcon(
                        symbolName: systemStatus.battery.symbolName,
                        tint: systemStatus.battery.tintColor,
                        accessibilityDescription: systemStatus.battery.accessibilityDescription,
                    )
                    WorkspaceSidebarStatusMiniIcon(
                        symbolName: systemStatus.audio.symbolName,
                        tint: systemStatus.audio.tintColor,
                        accessibilityDescription: systemStatus.audio.accessibilityDescription,
                    )
                    WorkspaceSidebarStatusMiniIcon(
                        symbolName: systemStatus.network.symbolName,
                        tint: systemStatus.network.tintColor,
                        accessibilityDescription: systemStatus.network.accessibilityDescription,
                    )
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(width: sectionWidth, height: 44, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.070),
                            Color.white.opacity(0.035),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing,
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.085), lineWidth: 0.5)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
    }
}
