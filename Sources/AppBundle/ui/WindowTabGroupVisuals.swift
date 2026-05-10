import AppKit
import Common
import SwiftUI

struct WindowTabGroupVisualView: View {
    let strip: WindowTabStripViewModel
    let drawsMockTabs: Bool

    var body: some View {
        GeometryReader { proxy in
            WindowTabGroupFrameView(
                strip: strip,
                groupSize: proxy.size,
                drawsMockTabs: drawsMockTabs,
            )
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .windowTabOcclusionMasked(
            panelFrame: strip.groupFrame,
            occludingScreenFrames: strip.occludingFloatingWindowFrames,
        )
    }
}

struct WindowTabGroupFrameView: View {
    let strip: WindowTabStripViewModel
    let groupSize: CGSize
    let drawsMockTabs: Bool

    var body: some View {
        let tabHeight = min(strip.frame.height, groupSize.height)
        let innerFrame = windowTabGroupInnerAppFrame(groupSize: groupSize, tabHeight: tabHeight)
        let appCornerRadius = strip.activeWindowCornerRadius
        let topInnerCornerRadius = windowTabGroupTopInnerCornerRadius(appCornerRadius)
        let outerTopRadius = windowTabGroupOuterCornerRadius(innerCornerRadius: topInnerCornerRadius)

        let bottomOuterRadius = appCornerRadius + windowTabGroupShellHorizontalInset()
        let outerRadii = PreviewCornerRadii(
            topLeft: outerTopRadius,
            topRight: outerTopRadius,
            bottomRight: bottomOuterRadius,
            bottomLeft: bottomOuterRadius
        )

        let innerRadii = PreviewCornerRadii(
            topLeft: topInnerCornerRadius,
            topRight: topInnerCornerRadius,
            bottomRight: appCornerRadius,
            bottomLeft: appCornerRadius
        )

        let shellShape = WindowTabGroupShellShape(
            outerRadii: outerRadii,
            innerRect: innerFrame,
            innerRadii: innerRadii
        )
        let outerShape = WindowTabDropOutlineShape(cornerRadii: outerRadii)

        ZStack(alignment: .topLeading) {
            shellShape
                .fill(mattePanelFill, style: FillStyle(eoFill: true))

            WindowTabGroupCornerShieldShape(
                innerRect: innerFrame,
                topRadius: windowTabGroupTopCornerShieldRadius(topInnerCornerRadius),
                bottomRadius: windowTabGroupBottomCornerShieldRadius(appCornerRadius)
            )
            .fill(mattePanelFill, style: FillStyle(eoFill: true))

            if drawsMockTabs {
                WindowTabGroupMockTabsView(
                    strip: strip,
                    stripWidth: groupSize.width,
                    stripHeight: tabHeight,
                )
                .frame(width: groupSize.width, height: tabHeight, alignment: .topLeading)
            }

            // Outer edge
            outerShape
                .strokeBorder(mattePanelBorder, lineWidth: windowTabGroupFrameStrokeWidth)

            // Inner window boundary
            WindowTabDropOutlineShape(cornerRadii: innerRadii)
                .strokeBorder(mattePanelInsetShadow, lineWidth: windowTabGroupFrameInnerStrokeWidth)
                .frame(width: innerFrame.width, height: innerFrame.height)
                .offset(x: innerFrame.minX, y: innerFrame.minY)
        }
        .frame(width: groupSize.width, height: groupSize.height)
        .shadow(color: Color.black.opacity(0.10), radius: 6, y: 2)
        .allowsHitTesting(false)
    }
}

struct WindowTabGroupMockTabsView: View {
    let strip: WindowTabStripViewModel
    let stripWidth: CGFloat
    let stripHeight: CGFloat

    var body: some View {
        let tabCount = max(strip.tabs.count, 1)
        let tabWidth = windowTabStripTabWidth(stripWidth: stripWidth, count: tabCount)
        let itemHeight = max(stripHeight - 4, 18)
        let visibleCount = windowTabGroupMockVisibleTabCount(
            stripWidth: stripWidth,
            tabWidth: tabWidth,
            tabCount: tabCount,
        )
        let visibleTabs = Array(strip.tabs.prefix(visibleCount))

        HStack(spacing: 0) {
            Color.clear
                .frame(width: windowTabStripReservedGroupHandleWidth())

            HStack(spacing: windowTabStripTabSpacing) {
                if visibleTabs.isEmpty {
                    WindowTabMockPillView(isActive: true)
                        .frame(width: tabWidth, height: itemHeight)
                } else {
                    ForEach(Array(visibleTabs.enumerated()), id: \.element.windowId) { index, tab in
                        WindowTabMockPillView(isActive: tab.isActive || (strip.activeWindowId == nil && index == 0))
                            .frame(width: tabWidth, height: itemHeight)
                    }
                }
            }
            .padding(.horizontal, windowTabStripContentHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            Color.clear
                .frame(width: windowTabStripReservedGroupHandleWidth())
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(width: stripWidth, height: stripHeight, alignment: .topLeading)
        .allowsHitTesting(false)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

struct WindowTabMockPillView: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.14 : 0.07))
                .padding(.vertical, 2)

            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(isActive ? 0.12 : 0.07), lineWidth: 0.5)
                .padding(.vertical, 2)
        }
    }
}

func windowTabGroupMockVisibleTabCount(stripWidth: CGFloat, tabWidth: CGFloat, tabCount: Int) -> Int {
    let requestedCount = max(tabCount, 1)
    let availableWidth = windowTabStripAvailableTabsWidth(stripWidth: stripWidth)
    guard availableWidth > 0 else { return 1 }
    let effectiveTabWidth = max(tabWidth + windowTabStripTabSpacing, 1)
    let fittingCount = Int(ceil((availableWidth + windowTabStripTabSpacing) / effectiveTabWidth))
    return max(1, min(requestedCount, fittingCount))
}

@MainActor
func windowTabGroupAppCornerRadius(activeWindowId: UInt32?) -> CGFloat {
    let radius = activeWindowId.map(estimatedWindowPreviewCornerRadius) ?? windowTabPreviewCornerRadius
    return min(max(radius, 6), windowTabGroupFrameMaxInnerCornerRadius)
}

func windowTabGroupOuterCornerRadius(innerCornerRadius _: CGFloat) -> CGFloat {
    windowTabStripCornerRadius
}

func windowTabGroupTopInnerCornerRadius(_ appCornerRadius: CGFloat) -> CGFloat {
    min(
        max(appCornerRadius + windowTabGroupShellHorizontalInset() + 14, windowTabStripCornerRadius + 18),
        windowTabGroupFrameMaxTopInnerCornerRadius
    )
}

func windowTabGroupTopCornerShieldRadius(_ topInnerCornerRadius: CGFloat) -> CGFloat {
    min(topInnerCornerRadius + windowTabGroupCornerShieldOverreach, windowTabGroupFrameMaxTopInnerCornerRadius)
}

func windowTabGroupBottomCornerShieldRadius(_ appCornerRadius: CGFloat) -> CGFloat {
    min(
        appCornerRadius + windowTabGroupCornerShieldOverreach,
        windowTabGroupFrameMaxInnerCornerRadius + windowTabGroupCornerShieldOverreach
    )
}

func windowTabGroupInnerAppFrame(groupSize: CGSize, tabHeight: CGFloat) -> CGRect {
    let horizontalInset = min(windowTabGroupShellHorizontalInset(), groupSize.width / 2)
    let contentTop = min(tabHeight + windowTabGroupShellTopInset(), groupSize.height)
    let availableHeight = max(groupSize.height - contentTop, 0)
    let bottomInset = min(windowTabGroupShellBottomInset(), availableHeight)

    return CGRect(
        x: horizontalInset,
        y: contentTop,
        width: max(groupSize.width - horizontalInset * 2, 0),
        height: max(availableHeight - bottomInset, 0)
    )
}

struct WindowTabGroupShellShape: Shape {
    let outerRadii: PreviewCornerRadii
    let innerRect: CGRect
    let innerRadii: PreviewCornerRadii

    func path(in rect: CGRect) -> Path {
        var path = WindowTabDropOutlineShape(cornerRadii: outerRadii).path(in: rect)
        if innerRect.width > 0, innerRect.height > 0 {
            path.addPath(WindowTabDropOutlineShape(cornerRadii: innerRadii).path(in: innerRect))
        }
        return path
    }
}

struct WindowTabGroupCornerShieldShape: Shape {
    let innerRect: CGRect
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    func path(in _: CGRect) -> Path {
        var path = Path()
        guard innerRect.width > 0, innerRect.height > 0 else { return path }
        let maxRadius = min(innerRect.width / 2, innerRect.height / 2)
        let resolvedTopRadius = min(topRadius, maxRadius)
        let resolvedBottomRadius = min(bottomRadius, maxRadius)

        if resolvedTopRadius > 0 {
            addTopLeftShield(to: &path, radius: resolvedTopRadius)
            addTopRightShield(to: &path, radius: resolvedTopRadius)
        }
        if resolvedBottomRadius > 0 {
            addBottomLeftShield(to: &path, radius: resolvedBottomRadius)
            addBottomRightShield(to: &path, radius: resolvedBottomRadius)
        }
        return path
    }

    func addTopLeftShield(to path: inout Path, radius: CGFloat) {
        let rect = CGRect(x: innerRect.minX, y: innerRect.minY, width: radius, height: radius)
        let center = CGPoint(x: innerRect.minX + radius, y: innerRect.minY + radius)
        path.addRect(rect)
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: innerRect.minY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(180),
            clockwise: true,
        )
        path.closeSubpath()
    }

    func addTopRightShield(to path: inout Path, radius: CGFloat) {
        let rect = CGRect(x: innerRect.maxX - radius, y: innerRect.minY, width: radius, height: radius)
        let center = CGPoint(x: innerRect.maxX - radius, y: innerRect.minY + radius)
        path.addRect(rect)
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: innerRect.minY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false,
        )
        path.closeSubpath()
    }

    func addBottomLeftShield(to path: inout Path, radius: CGFloat) {
        let rect = CGRect(x: innerRect.minX, y: innerRect.maxY - radius, width: radius, height: radius)
        let center = CGPoint(x: innerRect.minX + radius, y: innerRect.maxY - radius)
        path.addRect(rect)
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: innerRect.maxY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false,
        )
        path.closeSubpath()
    }

    func addBottomRightShield(to path: inout Path, radius: CGFloat) {
        let rect = CGRect(x: innerRect.maxX - radius, y: innerRect.maxY - radius, width: radius, height: radius)
        let center = CGPoint(x: innerRect.maxX - radius, y: innerRect.maxY - radius)
        path.addRect(rect)
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: innerRect.maxY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true,
        )
        path.closeSubpath()
    }
}

