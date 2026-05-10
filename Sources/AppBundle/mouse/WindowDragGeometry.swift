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

    func clampedPoint(_ point: CGPoint) -> CGPoint {
        let epsilon = CGFloat(0.001)
        return CGPoint(
            x: min(max(point.x, minX + epsilon), maxX - epsilon),
            y: min(max(point.y, minY + epsilon), maxY - epsilon),
        )
    }

    func isEqual(to other: Rect) -> Bool {
        topLeftX == other.topLeftX && topLeftY == other.topLeftY && width == other.width && height == other.height
    }

    var area: CGFloat {
        width * height
    }

    func intersection(_ other: Rect) -> Rect {
        let minX = max(self.minX, other.minX)
        let minY = max(self.minY, other.minY)
        let maxX = min(self.maxX, other.maxX)
        let maxY = min(self.maxY, other.maxY)
        return Rect(
            topLeftX: minX,
            topLeftY: minY,
            width: max(maxX - minX, 0),
            height: max(maxY - minY, 0),
        )
    }

    func isApproximatelyEqual(to other: Rect, tolerance: CGFloat) -> Bool {
        abs(topLeftX - other.topLeftX) <= tolerance &&
            abs(topLeftY - other.topLeftY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }

    func stackSplitPreviewRect(position: WindowStackSplitPosition) -> Rect? {
        let rawRect = switch position {
            case .left:
                Rect(topLeftX: topLeftX, topLeftY: topLeftY, width: width / 2, height: height)
            case .right:
                Rect(topLeftX: topLeftX + width / 2, topLeftY: topLeftY, width: width / 2, height: height)
            case .above:
                Rect(topLeftX: topLeftX, topLeftY: topLeftY, width: width, height: height / 2)
            case .below:
                Rect(topLeftX: topLeftX, topLeftY: topLeftY + height / 2, width: width, height: height / 2)
        }
        let previewRect = switch position {
            case .left:
                rawRect.insetBy(left: windowDropPreviewInset, right: 0, top: windowDropPreviewInset, bottom: windowDropPreviewInset)
            case .right:
                rawRect.insetBy(left: 0, right: windowDropPreviewInset, top: windowDropPreviewInset, bottom: windowDropPreviewInset)
            case .above:
                rawRect.insetBy(left: windowDropPreviewInset, right: windowDropPreviewInset, top: windowDropPreviewInset, bottom: 0)
            case .below:
                rawRect.insetBy(left: windowDropPreviewInset, right: windowDropPreviewInset, top: 0, bottom: windowDropPreviewInset)
        }
        guard previewRect.width > 0, previewRect.height > 0 else { return nil }
        return previewRect
    }
}

extension TilingContainer {
    @MainActor
    var windowTabDropZoneRect: Rect? {
        guard showsWindowTabs, let rect = windowDragVisibleRect else { return nil }
        return rect.tabInsertPreviewRect(barHeight: windowTabBarHeight)
    }

    @MainActor
    var windowTabDropInteractionRect: Rect? {
        guard showsWindowTabs, let rect = windowDragVisibleRect else { return nil }
        return rect.tabInsertInteractionRect(barHeight: windowTabBarHeight)
    }
}

func tabInteractionTopExclusion(_ interactionRect: Rect, in visibleRect: Rect) -> CGFloat {
    max(interactionRect.maxY - visibleRect.minY, 0)
}

extension TreeNode {
    @MainActor
    var centeredBodyDropZoneRect: Rect? {
        guard let rect = windowDragVisibleRect else { return nil }
        let topExclusion: CGFloat = switch self {
            case let window as Window:
                window.tabDropInteractionRect.map { tabInteractionTopExclusion($0, in: rect) } ?? rect.height * 0.2
            case let container as TilingContainer:
                container.windowTabDropInteractionRect.map { tabInteractionTopExclusion($0, in: rect) } ?? rect.height * 0.2
            default:
                max(rect.height * 0.2, 40)
        }
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
    func bodyDragIntent(at mouseLocation: CGPoint) -> WindowBodyDragIntent? {
        guard let swapRect = swapDropZoneRect else { return nil }
        if swapRect.contains(mouseLocation) {
            return .swap
        }
        for position in [WindowStackSplitPosition.left, .right, .above, .below] {
            if stackSplitDropZoneRect(position: position)?.contains(mouseLocation) == true {
                return .stackSplit(position)
            }
        }
        return nil
    }

    @MainActor
    func stackSplitDropZoneRect(position: WindowStackSplitPosition) -> Rect? {
        guard let centeredBodyRect = centeredBodyDropZoneRect,
              let sideBodyRect = sideBodyDropZoneRect,
              let swapRect = swapDropZoneRect
        else { return nil }
        return switch position {
            case .left:
                (swapRect.minX > sideBodyRect.minX)
                    ? Rect(
                        topLeftX: sideBodyRect.topLeftX,
                        topLeftY: sideBodyRect.topLeftY,
                        width: swapRect.minX - sideBodyRect.minX,
                        height: sideBodyRect.height,
                    )
                    : nil
            case .right:
                (sideBodyRect.maxX > swapRect.maxX)
                    ? Rect(
                        topLeftX: swapRect.maxX,
                        topLeftY: sideBodyRect.topLeftY,
                        width: sideBodyRect.maxX - swapRect.maxX,
                        height: sideBodyRect.height,
                    )
                    : nil
            case .above:
                (swapRect.minY > centeredBodyRect.minY)
                    ? Rect(
                        topLeftX: swapRect.topLeftX,
                        topLeftY: centeredBodyRect.topLeftY,
                        width: swapRect.width,
                        height: swapRect.minY - centeredBodyRect.minY,
                    )
                    : nil
            case .below:
                (centeredBodyRect.maxY > swapRect.maxY)
                    ? Rect(
                        topLeftX: swapRect.topLeftX,
                        topLeftY: swapRect.maxY,
                        width: swapRect.width,
                        height: centeredBodyRect.maxY - swapRect.maxY,
                    )
                    : nil
        }
    }

    @MainActor
    func stackSplitPreviewRect(position: WindowStackSplitPosition) -> Rect? {
        windowDragVisibleRect?.stackSplitPreviewRect(position: position)
    }

    @MainActor
    var swapDropZoneRect: Rect? {
        guard let bodyRect = centeredBodyDropZoneRect else { return nil }
        let swapWidth = min(bodyRect.width, max(bodyRect.width * 0.2, 28))
        let swapHeight = min(bodyRect.height, max(bodyRect.height * 0.2, 28))
        let swapRect = Rect(
            topLeftX: bodyRect.topLeftX + (bodyRect.width - swapWidth) / 2,
            topLeftY: bodyRect.topLeftY + (bodyRect.height - swapHeight) / 2,
            width: swapWidth,
            height: swapHeight,
        )
        guard swapRect.width > 0, swapRect.height > 0 else { return nil }
        return swapRect
    }
}

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
