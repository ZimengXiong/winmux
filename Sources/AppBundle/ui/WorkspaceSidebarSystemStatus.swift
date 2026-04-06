import Foundation
import IOKit.ps
import ISSoundAdditions
import SystemConfiguration

struct WorkspaceSidebarSystemStatusSnapshot: Equatable {
    let battery: WorkspaceSidebarBatterySnapshot
    let audio: WorkspaceSidebarAudioSnapshot
    let network: WorkspaceSidebarNetworkSnapshot

    static func current() -> Self {
        .init(
            battery: .current(),
            audio: .current(),
            network: .current(),
        )
    }
}

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
                if let chargePercent {
                    return "\(chargePercent)%"
                }
                return "--"
            case .ac:
                if let chargePercent {
                    return "AC \(chargePercent)%"
                }
                return "AC"
            case .unavailable:
                return "No Battery"
        }
    }

    var symbolName: String {
        switch state {
            case .charging:
                return "bolt.fill"
            case .ac:
                return "powerplug.fill"
            case .discharging:
                return "battery.100percent"
            case .unavailable:
                return "powerplug"
        }
    }

    var accessibilityDescription: String {
        switch state {
            case .charging:
                if let chargePercent {
                    return "Battery \(chargePercent) percent, charging"
                }
                return "Battery charging"
            case .ac:
                if let chargePercent {
                    return "Battery \(chargePercent) percent, on AC power"
                }
                return "AC power connected"
            case .discharging:
                if let chargePercent {
                    return "Battery \(chargePercent) percent, discharging"
                }
                return "Battery discharging"
            case .unavailable:
                return "No battery detected"
        }
    }

    static func current() -> Self {
        guard let powerSourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSources = IOPSCopyPowerSourcesList(powerSourceInfo)?.takeRetainedValue() as NSArray?
        else {
            return .init(chargePercent: nil, state: .unavailable)
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

            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isPluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let state: WorkspaceSidebarBatteryState
            if isCharging {
                state = .charging
            } else if isPluggedIn {
                state = .ac
            } else {
                state = .discharging
            }

            return .init(chargePercent: chargePercent, state: state)
        }

        return .init(chargePercent: nil, state: .unavailable)
    }
}

struct WorkspaceSidebarAudioSnapshot: Equatable {
    let volumePercent: Int?
    let isMuted: Bool

    var label: String {
        if isMuted {
            return "Mute"
        }
        if let volumePercent {
            return "\(volumePercent)%"
        }
        return "Audio"
    }

    var symbolName: String {
        if isMuted {
            return "speaker.slash.fill"
        }
        guard let volumePercent else {
            return "speaker.slash"
        }
        switch volumePercent {
            case ..<34:
                return "speaker.wave.1.fill"
            case ..<67:
                return "speaker.wave.2.fill"
            default:
                return "speaker.wave.3.fill"
        }
    }

    var accessibilityDescription: String {
        if isMuted {
            return "Sound muted"
        }
        if let volumePercent {
            return "Sound output volume \(volumePercent) percent"
        }
        return "Sound output unavailable"
    }

    static func current() -> Self {
        let isMuted = Sound.output.isMuted
        let volumePercent = (try? Sound.output.readVolume())
            .map { Int(($0 * 100).rounded()) }
        return .init(volumePercent: volumePercent, isMuted: isMuted)
    }
}

struct WorkspaceSidebarNetworkSnapshot: Equatable {
    let interfaceName: String?

    var label: String {
        interfaceName?.uppercased() ?? "Offline"
    }

    var symbolName: String {
        interfaceName == nil ? "network.slash" : "network"
    }

    var accessibilityDescription: String {
        if let interfaceName {
            return "Primary network interface \(interfaceName)"
        }
        return "No active network interface"
    }

    static func current() -> Self {
        .init(interfaceName: primaryInterfaceName())
    }

    private static func primaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "WinMuxWorkspaceSidebar" as CFString, nil, nil) else {
            return nil
        }

        let primaryInterfaceKey = "PrimaryInterface"
        let globalStatePaths = [
            "State:/Network/Global/IPv4",
            "State:/Network/Global/IPv6",
        ]

        for path in globalStatePaths {
            guard let state = SCDynamicStoreCopyValue(store, path as CFString) as? [String: Any],
                  let interfaceName = state[primaryInterfaceKey] as? String,
                  !interfaceName.isEmpty
            else {
                continue
            }
            return interfaceName
        }

        return nil
    }
}
