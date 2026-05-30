import AppKit
import SwiftUI

extension WorkspaceSidebarView {
    var sidebarShape: some Shape {
        WorkspaceSidebarPanelShape(rightCornerRadius: workspaceSidebarPanelRightCornerRadius)
    }

    func sidebarSurface<S: Shape>(in shape: S) -> some View {
        ZStack {
            sidebarGlassBase(in: shape)
            shape.fill(Color.black.opacity(sidebarGlassScrimOpacity))
            shape.fill(sidebarGlassTint.opacity(sidebarGlassTintOpacity))
                .blendMode(.plusLighter)
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(sidebarGlassHighlightPeak), location: 0),
                        .init(color: Color.white.opacity(sidebarGlassHighlightPeak * 0.25), location: 0.12),
                        .init(color: Color.clear, location: 0.45),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blendMode(.screen)
            shape.stroke(Color.white.opacity(sidebarGlassBorderOpacity), lineWidth: 0.5)
        }
        .compositingGroup()
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func sidebarGlassBase<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.interactive(false), in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
    }

    func sidebarSwipeCaptureOverlay(expansionProgress: CGFloat) -> some View {
        WorkspaceSidebarProjectSwipeScrollCapture(
            isEnabled: !snapshot.projects.isEmpty,
            onChanged: { horizontalTranslation, verticalTranslation in
                handleProjectSwipeChanged(
                    horizontalTranslation: horizontalTranslation,
                    verticalTranslation: verticalTranslation,
                    expansionProgress: expansionProgress,
                )
            },
            onEnded: { horizontalTranslation, verticalTranslation in
                handleProjectSwipeEnded(
                    horizontalTranslation: horizontalTranslation,
                    verticalTranslation: verticalTranslation,
                    expansionProgress: expansionProgress,
                )
            },
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private let sidebarGlassTint = Color(hue: 0, saturation: 0, brightness: 0.50)
private let sidebarGlassTintOpacity: Double = 0.06
private let sidebarGlassScrimOpacity: Double = 0.58
private let sidebarGlassHighlightPeak: Double = 0.08
private let sidebarGlassBorderOpacity: Double = 0.10

private struct WorkspaceSidebarPanelShape: Shape {
    let rightCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(rightCornerRadius, rect.width / 2, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
