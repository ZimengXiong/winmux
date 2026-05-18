import SwiftUI

struct WindowDragCursorProxyContent: Equatable {
    let label: String
    let isGroup: Bool
}

extension WindowDragCursorProxyPanel {
    func updateContent(label: String, isGroup: Bool) {
        let nextContent = WindowDragCursorProxyContent(label: label, isGroup: isGroup)
        guard currentContent != nextContent else { return }
        hostingView.rootView = AnyView(WindowDragCursorProxyView(label: label, isGroup: isGroup))
        currentContent = nextContent
    }
}

func windowDragCursorProxySize(label: String) -> CGSize {
    CGSize(width: min(max(CGFloat(label.count) * 7 + 36, 80), 200), height: 28)
}
