import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func handleSectionClick() {
        guard allowsWorkspaceActivation else { return }
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
        guard !workspaceSidebarPayload(payload, comesFromWorkspace: workspace.name) else {
            actions.send(.clearDropPreview)
            WindowDragCursorProxyPanel.shared.hide()
            return
        }
        switch payload {
            case .window(let windowId):
                actions.send(.moveWindow(windowId, toWorkspace: workspace.name))
            case .tabGroup(let representativeWindowId):
                actions.send(.moveTabGroup(representativeWindowId, toWorkspace: workspace.name))
        }
    }
}

@MainActor
private func workspaceSidebarPayload(_ payload: WorkspaceSidebarDragPayload, comesFromWorkspace workspaceName: String) -> Bool {
    switch payload {
        case .window(let windowId):
            return Window.get(byId: windowId)?.nodeWorkspace?.name == workspaceName
        case .tabGroup(let representativeWindowId):
            guard let window = Window.get(byId: representativeWindowId) else { return false }
            return dragSubjectNode(for: window, subject: .group).nodeWorkspace?.name == workspaceName
    }
}
