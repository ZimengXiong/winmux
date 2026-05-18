import SwiftUI

struct WorkspaceSidebarOptionalDragModifier: ViewModifier {
    let isEnabled: Bool
    let onChanged: () -> Void
    let onEnded: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { _ in onChanged() }
                    .onEnded { _ in onEnded() },
            )
        } else {
            content
        }
    }
}
