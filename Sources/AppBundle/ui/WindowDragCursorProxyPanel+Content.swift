import SwiftUI

struct WindowDragCursorProxyContent: Equatable {
    let label: String
    let isGroup: Bool
    let preview: WorkspaceSidebarDropPreviewViewModel?

    init(label: String, isGroup: Bool, preview: WorkspaceSidebarDropPreviewViewModel? = nil) {
        self.label = label
        self.isGroup = isGroup
        self.preview = preview
    }
}

extension WindowDragCursorProxyPanel {
    func updateContent(label: String, isGroup: Bool) {
        let nextContent = WindowDragCursorProxyContent(label: label, isGroup: isGroup)
        guard currentContent != nextContent else { return }
        hostingView.rootView = AnyView(WindowDragCursorProxyView(label: label, isGroup: isGroup))
        currentContent = nextContent
    }

    func updateContent(preview: WorkspaceSidebarDropPreviewViewModel) {
        let nextContent = WindowDragCursorProxyContent(
            label: preview.label,
            isGroup: preview.isTabGroup,
            preview: preview,
        )
        guard currentContent != nextContent else { return }
        hostingView.rootView = AnyView(WindowDragCursorProxyView(preview: preview))
        currentContent = nextContent
    }
}

func windowDragCursorProxySize(label: String) -> CGSize {
    CGSize(width: min(max(CGFloat(label.count) * 7 + 42, 96), 224), height: 28)
}
