import SwiftUI

struct WindowIntentPreviewGridView: View {
    let zones: [WindowIntentPreviewLocalZone]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(WindowIntentPreviewPalette.gridBaseFill)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(WindowIntentPreviewPalette.gridOuterStroke, lineWidth: borderLineWidth)
                }

            ForEach(zones) { zone in
                WindowIntentPreviewGridZoneView(zone: zone)
            }

            WindowIntentPreviewGridLines()
                .stroke(
                    WindowIntentPreviewPalette.gridLineStroke,
                    style: StrokeStyle(lineWidth: borderLineWidth, lineCap: .butt, lineJoin: .miter)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .compositingGroup()
    }

    private var cornerRadius: CGFloat {
        let frame = zones.map(\.frame).reduce(nil) { $0?.union($1) ?? $1 } ?? .zero
        return min(max(min(frame.width, frame.height) * 0.018, 10), 14)
    }

    private var borderLineWidth: CGFloat {
        3
    }
}

private struct WindowIntentPreviewGridZoneView: View {
    let zone: WindowIntentPreviewLocalZone

    var body: some View {
        ZStack {
            Rectangle()
                .fill(WindowIntentPreviewPalette.gridZoneFill(isActive: zone.isActive))
            if let symbol = zone.intentSymbolName {
                Image(systemName: symbol)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(WindowIntentPreviewPalette.gridSymbol(isActive: zone.isActive))
            }
        }
        .frame(width: zone.frame.width, height: zone.frame.height)
        .offset(x: zone.frame.minX, y: zone.frame.minY)
    }

    private var iconSize: CGFloat {
        min(max(min(zone.frame.width, zone.frame.height) * 0.42, 14), 42)
    }
}

private extension WindowIntentPreviewLocalZone {
    var intentSymbolName: String? {
        switch geometry {
            case .tabStrip:
                "rectangle.3.group"
            case .splitLeft:
                "arrow.left"
            case .splitRight:
                "arrow.right"
            case .splitAbove:
                "arrow.up"
            case .splitBelow:
                "arrow.down"
            case .rounded:
                windowIntentPreviewSymbolName(for: style, isGroup: false)
        }
    }
}
