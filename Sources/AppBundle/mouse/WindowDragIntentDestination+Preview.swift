extension WindowDragIntentDestination {
    @MainActor
    func preview(sourceWindowId: UInt32) -> WindowTabDropPreviewViewModel {
        WindowTabDropPreviewViewModel(
            containerFrame: previewContainerRect.toAppKitScreenRect,
            frame: previewRect.toAppKitScreenRect,
            title: title,
            subtitle: subtitle,
            style: previewStyle,
            geometry: previewGeometry,
            isGroup: isGroup,
            referenceWindowId: previewReferenceWindowId(sourceWindowId: sourceWindowId),
            isPointerSettled: WindowDragFrameGate.shared.state(for: sourceWindowId)?.isSettled ?? false,
            zones: previewZones.map(\.viewModel),
        )
    }

    func previewReferenceWindowId(sourceWindowId: UInt32) -> UInt32? {
        switch kind {
            case .tabStack(let targetWindowId), .stackSplit(let targetWindowId, _), .swap(let targetWindowId):
                return targetWindowId
            case .detachTab(let windowId):
                return windowId
            case .moveToWorkspace, .createWorkspace, .sidebarHover:
                return sourceWindowId
        }
    }

    func withPreviewZones(_ zones: [WindowDragIntentPreviewZone]) -> WindowDragIntentDestination {
        WindowDragIntentDestination(
            kind: kind,
            previewContainerRect: previewContainerRect,
            previewRect: previewRect,
            interactionRect: interactionRect,
            title: title,
            subtitle: subtitle,
            previewStyle: previewStyle,
            previewGeometry: previewGeometry,
            isGroup: isGroup,
            previewZones: zones,
        )
    }
}
