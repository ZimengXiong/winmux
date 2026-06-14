struct WindowStackSplitPreview {
    let rect: Rect
    let geometry: WindowTabDropPreviewGeometry
}

func shouldUseStickyWindowDragIntent(previewStyle: WindowTabDropPreviewStyle) -> Bool {
    switch previewStyle {
        case .tabInsert, .stackSplit, .swap:
            return true
        case .detach, .workspaceMove, .sidebarWorkspaceMove:
            return false
    }
}
