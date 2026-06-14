import AppKit
import Common

extension Rect {
    func stackSplitPreviewRect(position: WindowStackSplitPosition) -> Rect? {
        let rawRect = stackSplitRawPreviewRect(position: position)
        let previewRect = stackSplitInsetPreviewRect(rawRect, position: position)
        guard previewRect.width > 0, previewRect.height > 0 else { return nil }
        return previewRect
    }

    private func stackSplitRawPreviewRect(position: WindowStackSplitPosition) -> Rect {
        switch position {
            case .left:
                Rect(topLeftX: topLeftX, topLeftY: topLeftY, width: width / 2, height: height)
            case .right:
                Rect(topLeftX: topLeftX + width / 2, topLeftY: topLeftY, width: width / 2, height: height)
            case .above:
                Rect(topLeftX: topLeftX, topLeftY: topLeftY, width: width, height: height / 2)
            case .below:
                Rect(topLeftX: topLeftX, topLeftY: topLeftY + height / 2, width: width, height: height / 2)
        }
    }

    private func stackSplitInsetPreviewRect(_ rawRect: Rect, position: WindowStackSplitPosition) -> Rect {
        switch position {
            case .left:
                rawRect.insetBy(left: windowDropPreviewInset, right: 0, top: windowDropPreviewInset, bottom: windowDropPreviewInset)
            case .right:
                rawRect.insetBy(left: 0, right: windowDropPreviewInset, top: windowDropPreviewInset, bottom: windowDropPreviewInset)
            case .above:
                rawRect.insetBy(left: windowDropPreviewInset, right: windowDropPreviewInset, top: windowDropPreviewInset, bottom: 0)
            case .below:
                rawRect.insetBy(left: windowDropPreviewInset, right: windowDropPreviewInset, top: 0, bottom: windowDropPreviewInset)
        }
    }
}
