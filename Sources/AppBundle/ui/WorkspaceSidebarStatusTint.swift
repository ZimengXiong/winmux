import SwiftUI

extension WorkspaceSidebarBatterySnapshot {
    var tintColor: Color {
        switch state {
            case .charging:
                return Color(nsColor: .systemGreen)
            case .ac:
                return Color(nsColor: .systemGreen)
            case .discharging:
                return Color(nsColor: .systemOrange)
            case .unavailable:
                return Color.secondary
        }
    }
}

extension WorkspaceSidebarAudioSnapshot {
    var tintColor: Color {
        isMuted ? Color.secondary : Color(nsColor: .systemGreen)
    }
}

extension WorkspaceSidebarNetworkSnapshot {
    var tintColor: Color {
        interfaceName == nil ? Color.secondary : Color(nsColor: .systemBlue)
    }
}
