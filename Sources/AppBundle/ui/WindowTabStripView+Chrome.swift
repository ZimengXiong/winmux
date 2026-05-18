import AppKit
import SwiftUI

extension WindowTabStripView {
    func groupDragGesture(for windowId: UInt32?) -> some Gesture {
        DragGesture(minimumDistance: windowTabStripGroupDragMinimumDistance, coordinateSpace: .global)
            .onChanged { _ in
                noteCurrentMousePointerSample()
                guard let windowId,
                      shouldAllowTabStripChromeGroupDrag(windowId: windowId)
                else { return }
                updateMoveFromTabStrip(windowId)
            }
            .onEnded { _ in
                noteCurrentMousePointerSample()
                guard let windowId,
                      shouldContinueCurrentGroupDrag(windowId: windowId)
                else { return }
                finishMoveFromTabStrip()
            }
    }

    func windowTabStripShape(outerTopRadius: CGFloat) -> WindowTabDropOutlineShape {
        WindowTabDropOutlineShape(cornerRadii: PreviewCornerRadii(
            topLeft: outerTopRadius,
            topRight: outerTopRadius,
            bottomRight: 0,
            bottomLeft: 0
        ))
    }
}
