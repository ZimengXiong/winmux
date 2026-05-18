import AppKit
import SwiftUI

extension WorkspaceSidebarView {
    var sidebarShape: some Shape {
        Rectangle()
    }

    func sidebarSurface<S: Shape>(in shape: S) -> some View {
        shape
            .fill(workspaceSidebarPanelFill)
            .overlay {
                shape.stroke(workspaceSidebarPanelSeparator.opacity(0.34), lineWidth: 0.5)
            }
            .ignoresSafeArea()
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

private let workspaceSidebarPanelFill = Color(nsColor: NSColor(
    srgbRed: 0.09,
    green: 0.092,
    blue: 0.10,
    alpha: 0.92
))

private let workspaceSidebarPanelSeparator = Color.white.opacity(0.10)
