import AppKit
import SwiftUI

extension WorkspaceSidebarView {
    var sidebarShape: some Shape {
        Rectangle()
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

private let sidebarGlassTint = Color(hue: 0.61, saturation: 0.45, brightness: 0.55)
private let sidebarGlassTintOpacity: Double = 0.14
private let sidebarGlassScrimOpacity: Double = 0.55
private let sidebarGlassHighlightPeak: Double = 0.12
private let sidebarGlassBorderOpacity: Double = 0.10
