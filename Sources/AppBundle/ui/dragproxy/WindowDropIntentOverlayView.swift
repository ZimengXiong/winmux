import SwiftUI

struct WindowDropIntentOverlayView: View {
    let model: WindowDropIntentOverlayModel

    private let borderLineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(WindowIntentPreviewPalette.gridBaseFill)

            ForEach(localZones) { zone in
                dropZoneView(zone)
            }

            WindowIntentPreviewGridLines()
                .stroke(
                    WindowIntentPreviewPalette.gridLineStroke,
                    style: StrokeStyle(lineWidth: borderLineWidth, lineCap: .butt, lineJoin: .miter)
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(WindowIntentPreviewPalette.gridOuterStroke, lineWidth: borderLineWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .frame(width: model.targetFrame.width, height: model.targetFrame.height)
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var cornerRadius: CGFloat {
        model.cornerRadius ?? min(max(min(model.targetFrame.width, model.targetFrame.height) * 0.018, 10), 14)
    }

    private var localZones: [WindowIntentZone] {
        WindowIntentZoneBuilder.zones(in: Rect(
            topLeftX: 0,
            topLeftY: 0,
            width: model.targetFrame.width,
            height: model.targetFrame.height
        ))
    }

    private func dropZoneView(_ zone: WindowIntentZone) -> some View {
        let isActive = zone.zone == model.activeZone
        return ZStack {
            Rectangle()
                .fill(WindowIntentPreviewPalette.gridZoneFill(isActive: isActive))
            if let name = symbolName(for: zone.zone) {
                Image(systemName: name)
                    .font(.system(size: iconSize(for: zone.frame), weight: .semibold))
                    .foregroundStyle(WindowIntentPreviewPalette.gridSymbol(isActive: isActive))
            }
        }
        .frame(width: zone.frame.width, height: zone.frame.height)
        .position(x: zone.frame.center.x, y: zone.frame.center.y)
    }

    private func symbolName(for zone: WindowDropZone) -> String? {
        switch zone {
            case .left:
                "arrow.left"
            case .right:
                "arrow.right"
            case .top:
                "arrow.up"
            case .bottom:
                "arrow.down"
            case .middle:
                "arrow.left.arrow.right"
            case .tab:
                "rectangle.3.group"
        }
    }

    private func iconSize(for frame: Rect) -> CGFloat {
        min(max(min(frame.width, frame.height) * 0.45, 14), 48)
    }
}
