import SwiftUI

struct WorkspaceSidebarOptionalDragModifier: ViewModifier {
    let isEnabled: Bool
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { _ in
                        noteCurrentMousePointerSample()
                        onChanged(MousePointerTracker.shared.currentSample.point)
                    }
                    .onEnded { _ in
                        noteCurrentMousePointerSample()
                        onEnded(MousePointerTracker.shared.currentSample.point)
                    },
            )
        } else {
            content
        }
    }
}
