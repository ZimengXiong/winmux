import AppKit

@MainActor
func workspaceSidebarCursorPreviewRect(at mouseLocation: CGPoint) -> Rect {
    workspaceSidebarCursorPreviewRect(at: mouseLocation, sidebarRect: WorkspaceSidebarPanel.shared.visibleScreenRectNormalized())
}

func workspaceSidebarCursorPreviewRect(at mouseLocation: CGPoint, sidebarRect: Rect?) -> Rect {
    let width: CGFloat = 184
    let height: CGFloat = 42
    if let sidebarRect {
        return workspaceSidebarCursorPreviewRect(
            at: mouseLocation,
            sidebarRect: sidebarRect,
            width: width,
            height: height,
        )
    }
    return Rect(topLeftX: mouseLocation.x + 16, topLeftY: mouseLocation.y - height - 12, width: width, height: height)
}
