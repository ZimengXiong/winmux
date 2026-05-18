import SwiftUI

struct WorkspaceSidebarDropDelegate: DropDelegate {
    let target: WorkspaceSidebarDropTargetKind
    let actions: WorkspaceSidebarActions
    let performPayloadDrop: @MainActor (WorkspaceSidebarDragPayload) -> Void
    @Binding var isTargeted: Bool
    @Binding var isSettling: Bool

    func validateDrop(info: DropInfo) -> Bool {
        let isValid = info.hasItemsConforming(to: [workspaceSidebarDragPayloadType])
        if isValid, isSettling {
            isSettling = false
        }
        return isValid
    }

    func dropEntered(info: DropInfo) {
        isSettling = false
        isTargeted = true
        loadPayload(from: info) { payload in
            guard isTargeted else { return }
            sendPreview(for: payload)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard !isSettling || isTargeted else { return nil }
        isTargeted = true
        loadPayload(from: info) { payload in
            guard isTargeted else { return }
            sendPreview(for: payload)
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
        isSettling = true
        clearPreviewAfterProviderCallbacksSettle()
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        isSettling = true
        clearPreviewAfterProviderCallbacksSettle()
        loadPayload(from: info, completion: performPayloadDrop)
        return true
    }

    private func sendPreview(for payload: WorkspaceSidebarDragPayload) {
        switch payload {
            case .window(let windowId):
                actions.send(.previewWindowDrop(windowId, target: target))
            case .tabGroup(let representativeWindowId):
                actions.send(.previewTabGroupDrop(representativeWindowId, target: target))
        }
    }

    private func loadPayload(from info: DropInfo, completion: @escaping @MainActor (WorkspaceSidebarDragPayload) -> Void) {
        guard let provider = info.itemProviders(for: [workspaceSidebarDragPayloadType]).first else { return }
        provider.loadDataRepresentation(forTypeIdentifier: workspaceSidebarDragPayloadType.identifier) { data, _ in
            guard let data,
                  let rawValue = String(data: data, encoding: .utf8),
                  let payload = WorkspaceSidebarDragPayload(encodedValue: rawValue)
            else { return }
            Task { @MainActor in
                completion(payload)
            }
        }
    }

    private func clearPreviewAfterProviderCallbacksSettle() {
        actions.send(.clearDropPreview)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            actions.send(.clearDropPreview)
        }
    }
}
