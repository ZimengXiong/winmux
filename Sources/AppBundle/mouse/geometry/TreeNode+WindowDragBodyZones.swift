import AppKit
import Common

extension TreeNode {
    @MainActor
    var centeredBodyDropZoneRect: Rect? {
        guard let rect = windowDragVisibleRect else { return nil }
        let topExclusion = windowDragTopExclusion(in: rect)
        let bodyRect = rect.insetBy(
            left: 2,
            right: 2,
            top: min(topExclusion, rect.height * 0.45),
            bottom: 2,
        )
        guard bodyRect.width > 0, bodyRect.height > 0 else { return nil }
        return bodyRect
    }

    @MainActor
    var sideBodyDropZoneRect: Rect? {
        guard let rect = windowDragVisibleRect else { return nil }
        let bodyRect = rect.insetBy(left: 2, right: 2, top: 2, bottom: 2)
        guard bodyRect.width > 0, bodyRect.height > 0 else { return nil }
        return bodyRect
    }

    @MainActor
    private func windowDragTopExclusion(in rect: Rect) -> CGFloat {
        switch self {
            case let window as Window:
                window.tabDropInteractionRect.map { tabInteractionTopExclusion($0, in: rect) } ?? rect.height * 0.2
            case let container as TilingContainer:
                container.windowTabDropInteractionRect.map { tabInteractionTopExclusion($0, in: rect) } ?? rect.height * 0.2
            default:
                max(rect.height * 0.2, 40)
        }
    }
}
