import AppKit

extension CGPoint {
    @MainActor
    func findWindowTabDropDestination(in tree: TilingContainer, excluding sourceWindow: Window) -> WindowDragIntentDestination? {
        findWindowTabDropDestination(in: tree as TreeNode, excluding: sourceWindow)
    }

    @MainActor
    func findWindowTabDropDestination(in node: TreeNode, excluding sourceWindow: Window) -> WindowDragIntentDestination? {
        guard node.windowDragVisibleRect?.contains(self) == true else { return nil }
        switch node.tilingTreeNodeCasesOrDie() {
            case .window(let window):
                guard window != sourceWindow else { return nil }
                return tabStackDestination(targetWindow: window, mouseLocation: self)
            case .tilingContainer(let container):
                return findWindowTabDropDestinationInContainer(container, excluding: sourceWindow)
        }
    }

    @MainActor
    private func findWindowTabDropDestinationInContainer(
        _ container: TilingContainer,
        excluding sourceWindow: Window,
    ) -> WindowDragIntentDestination? {
        if let targetWindow = container.tabActiveWindow, targetWindow != sourceWindow,
           let destination = tabStackDestination(targetWindow: targetWindow, mouseLocation: self)
        {
            return destination
        }

        switch container.layout {
            case .tiles:
                return findWindowTabDropDestinationInChildren(container, excluding: sourceWindow)
            case .tabGroup:
                guard !container.usesWindowTabBehavior else { return nil }
                return findWindowTabDropDestinationInChildren(container, excluding: sourceWindow)
        }
    }

    @MainActor
    private func findWindowTabDropDestinationInChildren(
        _ container: TilingContainer,
        excluding sourceWindow: Window,
    ) -> WindowDragIntentDestination? {
        for child in container.childrenByMostRecentUse where child.windowDragVisibleRect?.contains(self) == true {
            if let destination = findWindowTabDropDestination(in: child, excluding: sourceWindow) {
                return destination
            }
        }
        return nil
    }
}
