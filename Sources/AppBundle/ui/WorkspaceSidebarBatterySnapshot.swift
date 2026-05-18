import Foundation
import IOKit.ps

enum WorkspaceSidebarBatteryState: Equatable {
    case charging
    case ac
    case discharging
    case unavailable
}

struct WorkspaceSidebarBatterySnapshot: Equatable {
    let chargePercent: Int?
    let state: WorkspaceSidebarBatteryState

    var label: String {
        switch state {
            case .charging, .discharging:
                chargePercent.map { "\($0)%" } ?? "--"
            case .ac:
                chargePercent.map { "AC \($0)%" } ?? "AC"
            case .unavailable:
                "No Battery"
        }
    }

    var symbolName: String {
        switch state {
            case .charging:
                "bolt.fill"
            case .ac:
                "powerplug.fill"
            case .discharging:
                "battery.100percent"
            case .unavailable:
                "powerplug"
        }
    }

    var accessibilityDescription: String {
        switch state {
            case .charging:
                chargePercent.map { "Battery \($0) percent, charging" } ?? "Battery charging"
            case .ac:
                chargePercent.map { "Battery \($0) percent, on AC power" } ?? "AC power connected"
            case .discharging:
                chargePercent.map { "Battery \($0) percent, discharging" } ?? "Battery discharging"
            case .unavailable:
                "No battery detected"
        }
    }

    static func current() -> Self {
        guard let powerSourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSources = IOPSCopyPowerSourcesList(powerSourceInfo)?.takeRetainedValue() as NSArray?
        else {
            return .init(chargePercent: nil, state: .unavailable)
        }

        for powerSource in powerSources {
            guard let snapshot = snapshot(powerSourceInfo: powerSourceInfo, powerSource: powerSource) else {
                continue
            }
            return snapshot
        }

        return .init(chargePercent: nil, state: .unavailable)
    }
}
