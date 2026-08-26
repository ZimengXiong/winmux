import SwiftUI

struct WindowDropIntentOverlayView: View {
    let model: WindowDropIntentOverlayModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            overlaySurface(shape: shape)

            ForEach(localZones) { zone in
                dropZoneView(zone)
            }
        }
        .clipShape(shape)
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

    @ViewBuilder
    private func overlaySurface<S: Shape>(shape: S) -> some View {
        if config.workspaceSidebar.chromeStyle == .solid {
            // Intent feedback remains translucent even with solid chrome selected. The selected
            // color tints the shared glass material instead of replacing it with an opaque fill.
            ZStack {
                GlassSurface(shape: shape)
                shape.fill(config.workspaceSidebar.resolvedSolidChromeColor.opacity(0.42))
            }
            .clipShape(shape)
        } else {
            GlassSurface(
                shape: shape,
                style: .liquidGlass,
                solidColor: config.workspaceSidebar.resolvedSolidChromeColor
            )
        }
    }

    private func dropZoneView(_ zone: WindowIntentZone) -> some View {
        let isActive = zone.zone == model.activeZone
        let style = config.workspaceSidebar.chromeStyle
        let solidColor = config.workspaceSidebar.resolvedSolidChromeColor
        let activeShape = RoundedRectangle(cornerRadius: activeZoneCornerRadius(for: zone.frame), style: .continuous)
        return ZStack {
            if isActive {
                activeShape
                    .fill(WindowIntentPreviewPalette.activeZoneFill(style: style, solidColor: solidColor))
                    .overlay(alignment: .center) {
                        activeShape
                            .stroke(
                                WindowIntentPreviewPalette.activeZoneStroke(style: style, solidColor: solidColor),
                                lineWidth: StrokeToken.emphasis
                            )
                    }
                    .shadow(color: WindowIntentPreviewPalette.activeZoneGlow(style: style, solidColor: solidColor), radius: 10)
                    .transition(.opacity)
            }
            if let name = symbolName(for: zone.zone) {
                Image(systemName: name)
                    .font(.system(size: iconSize(for: zone.frame), weight: .semibold))
                    .foregroundStyle(WindowIntentPreviewPalette.zoneSymbol(isActive: isActive))
            }
        }
        .frame(width: zone.frame.width, height: zone.frame.height)
        .position(x: zone.frame.center.x, y: zone.frame.center.y)
        .animation(MotionToken.quick, value: model.activeZone)
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
        min(max(min(frame.width, frame.height) * 0.38, 14), 42)
    }

    private func activeZoneCornerRadius(for frame: Rect) -> CGFloat {
        min(max(min(frame.width, frame.height) * 0.08, RadiusToken.row), RadiusToken.section)
    }
}
