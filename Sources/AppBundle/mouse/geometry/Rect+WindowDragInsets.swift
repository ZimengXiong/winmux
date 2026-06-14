import AppKit
import Common

extension Rect {
    func insetBy(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> Rect {
        Rect(
            topLeftX: topLeftX + left,
            topLeftY: topLeftY + top,
            width: width - left - right,
            height: height - top - bottom,
        )
    }

    func expanded(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> Rect {
        insetBy(left: -left, right: -right, top: -top, bottom: -bottom)
    }

    func expanded(by amount: CGFloat) -> Rect {
        Rect(topLeftX: topLeftX - amount, topLeftY: topLeftY - amount, width: width + 2 * amount, height: height + 2 * amount)
    }
}
