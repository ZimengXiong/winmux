import AppKit
import SwiftUI

extension WindowTabStripView {
    func tabItem(
        _ tab: WindowTabItemViewModel,
        context: WindowTabStripLayoutContext,
        itemHeight: CGFloat,
    ) -> some View {
        Button {
            guard !isWindowTabStripDragInProgress() else { return }
            focusWindowFromTabStripClick(tab.windowId, fallbackWorkspace: tab.workspaceName)
        } label: {
            WindowTabItemView(
                tab: tab,
                width: context.tabWidth,
                height: itemHeight,
                isDragSource: draggingTabId == tab.windowId,
                isHovered: hoveredTabId == tab.windowId
            )
        }
        .buttonStyle(.plain)
        .offset(x: tabVisualOffset(for: tab, context: context))
        .zIndex(draggingTabId == tab.windowId ? 1 : 0)
        .shadow(
            color: draggingTabId == tab.windowId ? Color.black.opacity(0.18) : Color.clear,
            radius: draggingTabId == tab.windowId ? 7 : 0,
            y: draggingTabId == tab.windowId ? 2 : 0,
        )
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: reorderTargetIndex(context: context))
        .highPriorityGesture(tabDragGesture(for: tab, context: context))
        .workspaceSidebarDrag(enabled: true) {
            WorkspaceSidebarDragPayload.window(tab.windowId).itemProvider
        }
        .onHover { hovering in
            updateHoveredTab(tab.windowId, hovering: hovering)
        }
        .contextMenu {
            Button("Remove Tab From Stack") {
                removeWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
            }
        }
    }
}
