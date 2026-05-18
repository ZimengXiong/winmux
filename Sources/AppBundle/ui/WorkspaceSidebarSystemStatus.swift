import Foundation

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
