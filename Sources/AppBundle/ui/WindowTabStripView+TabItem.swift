import AppKit
import SwiftUI

extension WindowTabStripView {
    func tabItem(
        _ tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        itemHeight: CGFloat,
    ) -> some View {
        WindowTabItemView(
            tab: tab,
            width: context.tabWidth,
            height: itemHeight,
            isDragSource: draggingTabId == tab.windowId,
            isHovered: hoveredTabId == tab.windowId,
            feedbackNamespace: tabFeedbackNamespace
        )
        .offset(x: tabVisualOffset(for: tab, context: context))
        .zIndex(draggingTabId == tab.windowId ? 1 : 0)
        .shadow(
            color: draggingTabId == tab.windowId ? Color.black.opacity(0.12) : Color.clear,
            radius: draggingTabId == tab.windowId ? 6 : 0,
            y: draggingTabId == tab.windowId ? 2 : 0,
        )
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: reorderTargetIndex(context: context))
        .gesture(tabDragGesture(for: tab, context: context))
        .workspaceSidebarDrag(enabled: true) {
            WorkspaceSidebarDragPayload.window(tab.windowId).itemProvider
        }
        .onHover { hovering in
            updateHoveredTab(tab.windowId, hovering: hovering)
        }
    }
}
