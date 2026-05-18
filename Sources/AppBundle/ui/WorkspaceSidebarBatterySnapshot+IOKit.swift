import Foundation
import IOKit.ps

extension WorkspaceSidebarBatterySnapshot {
    static func snapshot(powerSourceInfo: CFTypeRef, powerSource: Any) -> WorkspaceSidebarBatterySnapshot? {
        guard let powerSource = powerSource as AnyObject?,
              let description = IOPSGetPowerSourceDescription(powerSourceInfo, powerSource)?.takeUnretainedValue() as? [String: Any],
              let sourceType = description[kIOPSTypeKey] as? String,
              sourceType == kIOPSInternalBatteryType
        else {
            return nil
        }

        return .init(
            chargePercent: chargePercent(from: description),
            state: batteryState(from: description),
        )
    }

    private static func chargePercent(from description: [String: Any]) -> Int? {
        let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int
        let maxCapacity = description[kIOPSMaxCapacityKey] as? Int
        guard let currentCapacity, let maxCapacity, maxCapacity > 0 else { return nil }
        return Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
    }

    private static func batteryState(from description: [String: Any]) -> WorkspaceSidebarBatteryState {
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let isPluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        if isCharging {
            return .charging
        }
        return isPluggedIn ? .ac : .discharging
    }
}
