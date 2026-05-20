import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func handleSectionClick() {
        if isInUseOnOtherDisplay {
            activeInUseOverrideWorkspaceName = workspace.name
            return
        }
        if shouldHandleWorkspaceSidebarActivation(
            isEditing: false,
            isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()
        ) {
            actions.send(.selectWorkspace(workspace.name))
        }
    }

    func handlePayloadDrop(_ payload: WorkspaceSidebarDragPayload) {
        switch payload {
            case .window(let windowId):
                actions.send(.moveWindow(windowId, toWorkspace: workspace.name))
            case .tabGroup(let representativeWindowId):
                actions.send(.moveTabGroup(representativeWindowId, toWorkspace: workspace.name))
        }
    }
}
