import AppKit
import Foundation
import IOKit.ps
import SwiftUI

private let workspaceSidebarStatusCornerRadius: CGFloat = 10
private let workspaceSidebarStatusBatteryRefreshInterval: Duration = .seconds(30)

struct WorkspaceSidebarStatusView: View {
    let sectionWidth: CGFloat
    let isCompact: Bool

    @State private var batterySnapshot = WorkspaceSidebarBatterySnapshot.current()

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
                        batterySnapshot: batterySnapshot,
                        sectionWidth: sectionWidth,
                    )
                }
            }
        }
        .frame(width: sectionWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await refreshBatterySnapshot()
        }
        .animation(.easeInOut(duration: 0.16), value: isCompact)
    }

    private func refreshBatterySnapshot() async {
        batterySnapshot = .current()
        while !Task.isCancelled {
            try? await Task.sleep(for: workspaceSidebarStatusBatteryRefreshInterval)
            guard !Task.isCancelled else { return }
            batterySnapshot = .current()
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
    let batterySnapshot: WorkspaceSidebarBatterySnapshot
    let sectionWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.94))
                    .monospacedDigit()
                    .lineLimit(1)
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

            WorkspaceSidebarBatteryPill(snapshot: batterySnapshot)
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
        .accessibilityLabel(Text("\(date.formatted(date: .complete, time: .standard)), \(batterySnapshot.accessibilityDescription)"))
    }
}

private struct WorkspaceSidebarBatteryPill: View {
    let snapshot: WorkspaceSidebarBatterySnapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(snapshot.isCharging ? Color.accentColor : Color.secondary.opacity(0.75))

            Text(snapshot.label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.9))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.52))
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilityDescription)
    }
}

private struct WorkspaceSidebarBatterySnapshot: Equatable {
    let chargePercent: Int?
    let isCharging: Bool
    let isPluggedIn: Bool

    var label: String {
        if let chargePercent {
            return "\(chargePercent)%"
        }
        return isPluggedIn ? "AC" : "No Battery"
    }

    var symbolName: String {
        if chargePercent != nil {
            return isCharging ? "bolt.fill" : "battery.100percent"
        }
        return isPluggedIn ? "powerplug.fill" : "powerplug"
    }

    var accessibilityDescription: String {
        if let chargePercent {
            return isCharging
                ? "Battery \(chargePercent) percent, charging"
                : "Battery \(chargePercent) percent"
        }
        return isPluggedIn ? "AC power connected" : "No battery detected"
    }

    static func current() -> Self {
        guard let powerSourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSources = IOPSCopyPowerSourcesList(powerSourceInfo)?.takeRetainedValue() as NSArray?
        else {
            return .init(chargePercent: nil, isCharging: false, isPluggedIn: false)
        }

        for powerSource in powerSources {
            guard let powerSource = powerSource as AnyObject?,
                  let description = IOPSGetPowerSourceDescription(powerSourceInfo, powerSource)?.takeUnretainedValue() as? [String: Any],
                  let sourceType = description[kIOPSTypeKey] as? String,
                  sourceType == kIOPSInternalBatteryType
            else {
                continue
            }

            let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int
            let maxCapacity = description[kIOPSMaxCapacityKey] as? Int
            let chargePercent: Int? = if let currentCapacity, let maxCapacity, maxCapacity > 0 {
                Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
            } else {
                nil
            }

            return .init(
                chargePercent: chargePercent,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
            )
        }

        return .init(chargePercent: nil, isCharging: false, isPluggedIn: false)
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
