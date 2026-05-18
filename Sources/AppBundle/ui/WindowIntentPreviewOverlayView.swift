import SwiftUI

struct WindowIntentPreviewOverlayView: View {
    let model: WindowTabDropPreviewViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(localZones) { zone in
                WindowIntentPreviewZoneView(zone: zone)
            }
        }
        .frame(width: model.containerFrame.width, height: model.containerFrame.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var localZones: [WindowIntentPreviewLocalZone] {
        let zones = model.zones.isEmpty
            ? [WindowTabDropPreviewZoneViewModel(
                frame: model.frame,
                style: model.style,
                geometry: model.geometry,
                isActive: true,
            )]
            : model.zones
        return zones.map { zone in
            WindowIntentPreviewLocalZone(
                frame: localFrame(for: zone.frame),
                style: zone.style,
                geometry: zone.geometry,
                isActive: zone.isActive,
            )
        }
    }

    private func localFrame(for screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX - model.containerFrame.minX,
            y: model.containerFrame.height - (screenFrame.maxY - model.containerFrame.minY),
            width: screenFrame.width,
            height: screenFrame.height,
        )
    }
}

struct WindowIntentPreviewLocalZone: Identifiable {
    var id: String {
        "\(frame.debugDescription)-\(style)-\(geometry)-\(isActive)"
    }

    let frame: CGRect
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let isActive: Bool
}
