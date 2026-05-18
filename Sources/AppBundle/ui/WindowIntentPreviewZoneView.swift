import SwiftUI

struct WindowIntentPreviewZoneView: View {
    let zone: WindowIntentPreviewLocalZone

    var body: some View {
        ZStack {
            WindowTabDropOutlineShape(cornerRadii: zone.geometry.cornerRadii(radius: windowTabPreviewCornerRadius))
                .fill(WindowIntentPreviewPalette.fill)
            WindowTabDropOutlineShape(cornerRadii: zone.geometry.cornerRadii(radius: windowTabPreviewCornerRadius))
                .fill(WindowIntentPreviewPalette.highlight(style: zone.style, isActive: zone.isActive))
            WindowTabDropOutlineShape(cornerRadii: zone.geometry.cornerRadii(radius: windowTabPreviewCornerRadius))
                .strokeBorder(WindowIntentPreviewPalette.stroke(style: zone.style, isActive: zone.isActive), lineWidth: 1)
            if let line = windowIntentPreviewGuideLine(for: zone.geometry, in: zone.frame.size) {
                WindowIntentPreviewGuideShape(line: line)
                    .stroke(WindowIntentPreviewPalette.guide(style: zone.style, isActive: zone.isActive), lineWidth: 1.5)
            }
        }
        .frame(width: zone.frame.width, height: zone.frame.height)
        .offset(x: zone.frame.minX, y: zone.frame.minY)
    }
}

struct WindowIntentPreviewGuideShape: Shape {
    let line: WindowIntentPreviewGuideLine

    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: line.start)
        path.addLine(to: line.end)
        return path
    }
}
