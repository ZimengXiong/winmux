import SwiftUI

func workspaceSidebarProjectHue(projectId: WorkspaceProjectId) -> Double {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in projectId.rawValue.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return Double(hash % 360) / 360.0
}

func workspaceSidebarProjectColor(projectId: WorkspaceProjectId) -> Color {
    workspaceSidebarProjectColor(projectId: projectId, configuredHex: nil)
}

func workspaceSidebarProjectColor(projectId: WorkspaceProjectId, configuredHex: String?) -> Color {
    if let configuredHex, let color = workspaceSidebarColor(hex: configuredHex) {
        return color
    }
    return Color(
        hue: workspaceSidebarProjectHue(projectId: projectId),
        saturation: 0.30,
        brightness: 0.82,
    )
}
