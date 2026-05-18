import Foundation
import SystemConfiguration

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

        for path in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            guard let state = SCDynamicStoreCopyValue(store, path as CFString) as? [String: Any],
                  let interfaceName = state["PrimaryInterface"] as? String,
                  !interfaceName.isEmpty
            else {
                continue
            }
            return interfaceName
        }

        return nil
    }
}
