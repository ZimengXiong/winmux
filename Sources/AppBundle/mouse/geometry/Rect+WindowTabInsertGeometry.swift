import AppKit
import Common

extension Rect {
    func tabInsertPreviewRect(barHeight: CGFloat) -> Rect {
        let effectiveHeight = min(
            max(barHeight + windowTabInsertPreviewExtraHeight, windowTabInsertPreviewMinHeight),
            max(height, 0)
        )
        return insetBy(
            left: windowDropPreviewInset,
            right: windowDropPreviewInset,
            top: windowDropPreviewInset,
            bottom: max(height - effectiveHeight, 0),
        )
    }

    func tabInsertInteractionRect(barHeight: CGFloat) -> Rect {
        tabInsertPreviewRect(barHeight: barHeight).expanded(
            left: windowTabInsertInteractionHorizontalInset,
            right: windowTabInsertInteractionHorizontalInset,
            top: windowTabInsertInteractionTopInset,
            bottom: windowTabInsertInteractionBottomInset
        )
    }
}
