import AppKit
import Common

enum ResizePreviewPalette {
    static let fill = mattePanelNSColor.cgColor
    static let stroke = NSColor.white.withAlphaComponent(0.04).cgColor
    static let tabGroupBar = NSColor.white.withAlphaComponent(0.055).cgColor
    static let fallbackIconFill = NSColor.white.withAlphaComponent(0.12).cgColor
    static let sourceFrameFill = mattePanelNSColor.cgColor
    static let sourceFrameStroke = NSColor.white.withAlphaComponent(0.055).cgColor
    static let sourceMockTabFill = NSColor.white.withAlphaComponent(0.085).cgColor
    static let sourceMockTabStroke = NSColor.white.withAlphaComponent(0.075).cgColor
}

final class ResizePreviewDisabledLayerAction: NSObject, CAAction {
    func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {}
}

func disableResizePreviewLayerActions(_ layer: CALayer) {
    let action = ResizePreviewDisabledLayerAction()
    layer.actions = [
        "backgroundColor": action,
        "bounds": action,
        "contents": action,
        "cornerRadius": action,
        "frame": action,
        "hidden": action,
        "opacity": action,
        "path": action,
        "position": action,
        "sublayers": action,
        "transform": action,
    ]
}

struct ResizePreviewCornerRadii {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat

    static func uniform(_ radius: CGFloat) -> ResizePreviewCornerRadii {
        ResizePreviewCornerRadii(
            topLeft: radius,
            topRight: radius,
            bottomRight: radius,
            bottomLeft: radius
        )
    }
}

func windowResizePreviewTabGroupShellPath(in bounds: CGRect, headerHeight: CGFloat) -> CGPath {
    let path = CGMutablePath()
    guard bounds.width > 0, bounds.height > 0 else { return path }

    let shellInset = min(windowTabGroupShellHorizontalInset(), bounds.width / 2)
    let bottomInset = min(windowTabGroupShellBottomInset(), bounds.height)
    let tabHeight = min(max(headerHeight, 0), bounds.height)
    let contentHeight = max(bounds.height - tabHeight - bottomInset, 0)
    let innerRect = CGRect(
        x: bounds.minX + shellInset,
        y: bounds.minY + tabHeight,
        width: max(bounds.width - shellInset * 2, 0),
        height: contentHeight,
    )
    let appRadius = min(max(min(innerRect.width, innerRect.height) * 0.04, 8), 22)
    let topInnerRadius = min(max(appRadius + shellInset + 14, 30), 40)
    let bottomOuterRadius = appRadius + shellInset

    path.addPath(windowResizePreviewRoundedRectPath(
        in: bounds,
        radii: ResizePreviewCornerRadii(
            topLeft: 12,
            topRight: 12,
            bottomRight: bottomOuterRadius,
            bottomLeft: bottomOuterRadius,
        )
    ))
    if innerRect.width > 0, innerRect.height > 0 {
        path.addPath(windowResizePreviewRoundedRectPath(
            in: innerRect,
            radii: ResizePreviewCornerRadii(
                topLeft: topInnerRadius,
                topRight: topInnerRadius,
                bottomRight: appRadius,
                bottomLeft: appRadius,
            )
        ))
    }
    return path
}

func windowResizePreviewMockTabPillsPath(in bounds: CGRect, headerHeight: CGFloat, tabCount: Int) -> CGPath {
    let path = CGMutablePath()
    guard bounds.width > 0, bounds.height > 0 else { return path }

    let resolvedHeaderHeight = min(max(headerHeight, 18), bounds.height)
    let horizontalInset = min(windowTabGroupShellHorizontalInset(), bounds.width / 2)
    let handleWidth = windowTabStripReservedGroupHandleWidth()
    let contentPadding = windowTabStripContentPadding()
    let minX = bounds.minX + horizontalInset + handleWidth + contentPadding
    let maxX = bounds.maxX - horizontalInset - handleWidth - contentPadding
    let availableWidth = max(maxX - minX, 0)
    guard availableWidth > 0 else { return path }

    let visibleCount = windowResizePreviewMockTabVisibleCount(
        availableWidth: availableWidth,
        tabCount: tabCount,
        tabWidth: windowTabStripTabWidth(stripWidth: bounds.width, count: max(tabCount, 1)),
    )
    let tabWidth = min(windowTabStripTabWidth(stripWidth: bounds.width, count: max(tabCount, 1)), availableWidth)
    let tabHeight = max(resolvedHeaderHeight - 8, 10)
    let tabY = bounds.minY + (resolvedHeaderHeight - tabHeight) / 2
    var tabX = minX

    for _ in 0..<visibleCount {
        let remainingWidth = maxX - tabX
        guard remainingWidth >= 24 else { break }
        let rect = CGRect(
            x: tabX,
            y: tabY,
            width: min(tabWidth, remainingWidth),
            height: tabHeight,
        )
        let radius = min(12, rect.height / 2)
        path.addPath(windowResizePreviewRoundedRectPath(in: rect, radii: .uniform(radius)))
        tabX += tabWidth + windowResizePreviewMockTabSpacing
    }

    return path
}

let windowResizePreviewMockTabSpacing: CGFloat = 8

func windowResizePreviewMockTabVisibleCount(
    availableWidth: CGFloat,
    tabCount: Int,
    tabWidth: CGFloat,
) -> Int {
    let requestedCount = max(tabCount, 1)
    let effectiveWidth = max(tabWidth + windowResizePreviewMockTabSpacing, 1)
    let fittingCount = Int(ceil((availableWidth + windowResizePreviewMockTabSpacing) / effectiveWidth))
    return max(1, min(requestedCount, fittingCount))
}

func windowResizePreviewCornerRadius(for rect: CGRect) -> CGFloat {
    let minimumDimension = min(rect.width, rect.height)
    guard minimumDimension > 0 else { return 0 }
    return min(min(max(minimumDimension * 0.04, 8), 16), minimumDimension / 2)
}

func windowResizePreviewRoundedRectPath(in rect: CGRect, radii: ResizePreviewCornerRadii) -> CGPath {
    let path = CGMutablePath()
    guard rect.width > 0, rect.height > 0 else { return path }

    let maxRadius = min(rect.width, rect.height) / 2
    let topLeft = min(radii.topLeft, maxRadius)
    let topRight = min(radii.topRight, maxRadius)
    let bottomRight = min(radii.bottomRight, maxRadius)
    let bottomLeft = min(radii.bottomLeft, maxRadius)

    path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
    if topRight > 0 {
        path.addArc(
            center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
            radius: topRight,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: false,
        )
    }
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
    if bottomRight > 0 {
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
            radius: bottomRight,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: false,
        )
    }
    path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
    if bottomLeft > 0 {
        path.addArc(
            center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
            radius: bottomLeft,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: false,
        )
    }
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
    if topLeft > 0 {
        path.addArc(
            center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
            radius: topLeft,
            startAngle: .pi,
            endAngle: .pi * 1.5,
            clockwise: false,
        )
    }
    path.closeSubpath()
    return path
}

func windowResizePreviewStackOffset(_ index: Int, iconCount: Int, size: CGFloat) -> CGSize {
    let offsets = [
        CGSize(width: 0, height: -size * 0.08),
        CGSize(width: -size * 0.24, height: size * 0.16),
        CGSize(width: size * 0.24, height: size * 0.18),
        CGSize(width: -size * 0.02, height: size * 0.32),
    ]
    let offset = offsets[min(index, offsets.count - 1)]
    return iconCount == 2 && index == 1 ? CGSize(width: -size * 0.18, height: size * 0.16) : offset
}

func windowResizePreviewStackRotation(_ index: Int) -> Double {
    let rotations = [-4.0, 7.0, -8.0, 3.0]
    return rotations[min(index, rotations.count - 1)]
}

