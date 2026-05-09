import AppKit
import Foundation
import SwiftUI

private let workspaceSidebarStatusCornerRadius: CGFloat = 8
private let workspaceSidebarStatusRefreshInterval: Duration = .seconds(5)

struct WorkspaceSidebarStatusView: View {
    let sectionWidth: CGFloat
    let isCompact: Bool

    @State private var systemStatus = WorkspaceSidebarSystemStatusSnapshot.current()

    var body: some View {
        Group {
            if isCompact {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    WorkspaceSidebarCompactClockCard(
                        date: context.date,
                        sectionWidth: sectionWidth,
                    )
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    WorkspaceSidebarExpandedStatusCard(
                        date: context.date,
                        systemStatus: systemStatus,
                        sectionWidth: sectionWidth,
                    )
                }
            }
        }
        .frame(width: sectionWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await refreshSystemStatus()
        }
        .animation(.easeInOut(duration: 0.16), value: isCompact)
    }

    private func refreshSystemStatus() async {
        systemStatus = .current()
        while !Task.isCancelled {
            try? await Task.sleep(for: workspaceSidebarStatusRefreshInterval)
            guard !Task.isCancelled else { return }
            systemStatus = .current()
        }
    }
}

private struct WorkspaceSidebarCompactClockCard: View {
    let date: Date
    let sectionWidth: CGFloat

    private var components: WorkspaceSidebarClockComponents {
        WorkspaceSidebarClockComponents(date: date)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            Text(components.hour)
                .foregroundStyle(Color.white.opacity(0.86))

            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 12, height: 1)

            Text(components.minute)
                .foregroundStyle(Color.white.opacity(0.86))

            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 12, height: 1)

            Text(components.second)
                .foregroundStyle(Color.white.opacity(0.62))
        }
        .font(.system(size: 16, weight: .semibold))
        .monospacedDigit()
        .frame(width: sectionWidth, alignment: .center)
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

private struct WorkspaceSidebarExpandedStatusCard: View {
    let date: Date
    let systemStatus: WorkspaceSidebarSystemStatusSnapshot
    let sectionWidth: CGFloat

    @MainActor private var showsDate: Bool { config.workspaceSidebar.showDate }
    @MainActor private var showsStatusPills: Bool { config.workspaceSidebar.showStatusPills }

    private var accessibilitySummary: String {
        var parts: [String] = [
            date.formatted(date: .omitted, time: .standard),
        ]
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
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .allowsTightening(true)
                if showsDate {
                    Text(date, format: .dateTime.month(.wide).day())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            if showsStatusPills {
                HStack(alignment: .center, spacing: 12) {
                    WorkspaceSidebarStatusInlineItem(
                        symbolName: systemStatus.battery.symbolName,
                        label: systemStatus.battery.label,
                        accessibilityDescription: systemStatus.battery.accessibilityDescription,
                    )
                    WorkspaceSidebarStatusInlineItem(
                        symbolName: systemStatus.audio.symbolName,
                        label: systemStatus.audio.label,
                        accessibilityDescription: systemStatus.audio.accessibilityDescription,
                    )
                    WorkspaceSidebarStatusInlineItem(
                        symbolName: systemStatus.network.symbolName,
                        label: systemStatus.network.label,
                        accessibilityDescription: systemStatus.network.accessibilityDescription,
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: sectionWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.065))
                .overlay {
                    RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
    }
}

private struct WorkspaceSidebarStatusInlineItem: View {
    let symbolName: String
    let label: String
    let accessibilityDescription: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.56))
                .frame(width: 12, alignment: .center)

            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.70))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}

private struct WorkspaceSidebarBatteryPill: View {
    let snapshot: WorkspaceSidebarBatterySnapshot

    var body: some View {
        WorkspaceSidebarStatusPill(
            symbolName: snapshot.symbolName,
            label: snapshot.label,
            tint: snapshot.tintColor,
            accessibilityDescription: snapshot.accessibilityDescription,
        )
    }
}

private struct WorkspaceSidebarAudioPill: View {
    let snapshot: WorkspaceSidebarAudioSnapshot

    var body: some View {
        WorkspaceSidebarStatusPill(
            symbolName: snapshot.symbolName,
            label: snapshot.label,
            tint: snapshot.tintColor,
            accessibilityDescription: snapshot.accessibilityDescription,
        )
    }
}

private struct WorkspaceSidebarNetworkPill: View {
    let snapshot: WorkspaceSidebarNetworkSnapshot

    var body: some View {
        WorkspaceSidebarStatusPill(
            symbolName: snapshot.symbolName,
            label: snapshot.label,
            tint: snapshot.tintColor,
            accessibilityDescription: snapshot.accessibilityDescription,
        )
    }
}

private struct WorkspaceSidebarStatusPill: View {
    let symbolName: String
    let label: String
    let tint: Color
    let accessibilityDescription: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}

private extension WorkspaceSidebarBatterySnapshot {
    var tintColor: Color {
        switch state {
            case .charging:
                return Color(nsColor: .systemGreen)
            case .ac:
                return Color(nsColor: .systemGray)
            case .discharging:
                return Color(nsColor: .systemOrange)
            case .unavailable:
                return Color.secondary
        }
    }
}

private extension WorkspaceSidebarAudioSnapshot {
    var tintColor: Color {
        isMuted ? Color.secondary : Color(nsColor: .systemGreen)
    }
}

private extension WorkspaceSidebarNetworkSnapshot {
    var tintColor: Color {
        interfaceName == nil ? Color.secondary : Color(nsColor: .systemBlue)
    }
}

private struct WorkspaceSidebarClockComponents {
    let hour: String
    let minute: String
    let second: String

    init(date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        hour = Self.format(components.hour)
        minute = Self.format(components.minute)
        second = Self.format(components.second)
    }

    private static func format(_ value: Int?) -> String {
        String(format: "%02d", value ?? 0)
    }
}
