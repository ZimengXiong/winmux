import Foundation
import SwiftUI

struct WorkspaceSidebarExpandedStatusCard: View {
    let date: Date
    let systemStatus: WorkspaceSidebarSystemStatusSnapshot
    let sectionWidth: CGFloat

    @MainActor private var showsDate: Bool { config.workspaceSidebar.showDate }
    @MainActor private var showsStatusPills: Bool { config.workspaceSidebar.showStatusPills }

    private var accessibilitySummary: String {
        var parts = [date.formatted(date: .omitted, time: .standard)]
        if showsDate {
            parts.append(date.formatted(date: .complete, time: .omitted))
        }
        if showsStatusPills {
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
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(date, format: .dateTime.second(.twoDigits))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.40))
                    .lineLimit(1)
                    .baselineOffset(3)
            }
            if showsDate {
                Text(date, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .lineLimit(1)
                    .padding(.leading, 10)
            }
            Spacer(minLength: 0)
            if showsStatusPills {
                HStack(alignment: .center, spacing: 6) {
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
        .padding(.horizontal, 10)
        .frame(width: sectionWidth, height: 38, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
    }
}
