import SwiftUI

struct WorkspaceSidebarOptionalDragModifier: ViewModifier {
    let isEnabled: Bool
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void
    @State private var isDragging = false

    func body(content: Content) -> some View {
        if isEnabled {
            content.highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { _ in
                        if !isDragging {
                            isDragging = true
                            beginWorkspaceSidebarItemDrag()
                        }
                        noteCurrentMousePointerSample()
                        onChanged(MousePointerTracker.shared.currentSample.point)
                    }
                    .onEnded { _ in
                        noteCurrentMousePointerSample()
                        onEnded(MousePointerTracker.shared.currentSample.point)
                        if isDragging {
                            isDragging = false
                            endWorkspaceSidebarItemDrag()
                        }
                    },
            )
        } else {
            content
        }
    }
}
