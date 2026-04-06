import AppKit
import Foundation
import SwiftUI

private let workspaceSidebarStatusCornerRadius: CGFloat = 10
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
        VStack(spacing: 5) {
            Text(components.hour)
                .foregroundStyle(Color.primary.opacity(0.92))

            Capsule()
                .fill(Color.secondary.opacity(0.22))
                .frame(width: 12, height: 1)

            Text(components.minute)
                .foregroundStyle(Color.primary.opacity(0.92))

            Capsule()
                .fill(Color.secondary.opacity(0.22))
                .frame(width: 12, height: 1)

            Text(components.second)
                .foregroundStyle(Color.secondary.opacity(0.82))
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .monospacedDigit()
        .frame(width: sectionWidth, alignment: .center)
        .frame(minHeight: 84)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
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
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.94))
                    .monospacedDigit()
                    .lineLimit(1)
                if showsDate {
                    Text(date, format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.72))
                        .textCase(.uppercase)
                    Text(date, format: .dateTime.month(.abbreviated).day().year())
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            if showsStatusPills {
                HStack(alignment: .center, spacing: 6) {
                    WorkspaceSidebarBatteryPill(snapshot: systemStatus.battery)
                    WorkspaceSidebarAudioPill(snapshot: systemStatus.audio)
                    WorkspaceSidebarNetworkPill(snapshot: systemStatus.network)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: sectionWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
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
                .foregroundStyle(tint)

            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.9))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.16))
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 0.5)
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
