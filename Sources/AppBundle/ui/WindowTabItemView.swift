import AppKit
import Common
import SwiftUI

// MARK: - Tab Item View

struct WindowTabItemView: View {
    let tab: WindowTabItemViewModel
    let width: CGFloat
    let height: CGFloat
    let isDragSource: Bool
    let isHovered: Bool
    let feedbackNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        let iconSize = min(max(height - 14, 14), 18)
        let textWidth = max(width - iconSize - 34, 36)

        ZStack {
            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .fill(baseTabFill)
                .padding(.vertical, 2)

            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .fill(feedbackFill)
                .opacity(feedbackOpacity)
                .padding(.vertical, 2)
                .matchedGeometryEffect(id: feedbackId, in: feedbackNamespace)
                .allowsHitTesting(false)

            if isHovered, !tab.isActive {
                RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    .padding(.vertical, 2)
                    .allowsHitTesting(false)
            }

            Button {
                focusWindowFromTabStripClick(tab.windowId, fallbackWorkspace: tab.workspaceName)
            } label: {
                HStack(spacing: 8) {
                    appIcon(size: iconSize)

                    Text(tab.title)
                        .font(.system(size: 12, weight: tab.isActive ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .allowsTightening(false)
                        .foregroundStyle(foregroundColor)
                        .frame(width: textWidth, alignment: .leading)
                        .clipped()

                    Spacer(minLength: 0)
                }
                    .padding(.horizontal, 12)
                    .frame(width: width, height: height, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: width, height: height)

        }
        .frame(width: width, height: height)
        .clipped()
        .opacity(isDragSource ? 0.55 : 1.0)
        .scaleEffect(isDragSource ? 1.02 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDragSource)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove Tab From Stack") {
                removeWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
            }
        }
    }

    var feedbackId: String {
        isHovered ? "hover-pill" : "active-pill-\(tab.windowId)"
    }

    var tabIconText: String {
        tab.appName.first.map { String($0).uppercased() } ?? "W"
    }

    @ViewBuilder
    func appIcon(size: CGFloat) -> some View {
        if let icon = appIconImage(bundleIdentifier: tab.appBundleId, bundlePath: tab.appBundlePath) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size, alignment: .center)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Text(tabIconText)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(tab.isActive ? 0.86 : 0.62))
                .frame(width: size, height: size, alignment: .center)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(tab.isActive ? 0.22 : 0.14))
                }
                .accessibilityHidden(true)
        }
    }

    var baseTabFill: Color {
        tab.isActive ? Color.white.opacity(0.055) : Color.white.opacity(0.030)
    }

    var feedbackFill: Color {
        if isHovered {
            return Color.white.opacity(tab.isActive ? 0.12 : 0.08)
        }
        return tab.isActive ? Color.white.opacity(0.08) : Color.clear
    }

    var feedbackOpacity: Double {
        isHovered || tab.isActive ? 1 : 0
    }

    var foregroundColor: Color {
        if tab.isActive { return Color.white.opacity(0.95) }
        if isDragSource { return Color.white.opacity(0.80) }
        return isHovered ? Color.white.opacity(0.82) : Color.white.opacity(0.58)
    }
}

struct PreviewCornerRadii {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat

    static func uniform(_ radius: CGFloat) -> PreviewCornerRadii {
        PreviewCornerRadii(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
    }
}

struct WindowTabDropOutlineShape: InsettableShape {
    var cornerRadii: PreviewCornerRadii
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(cornerRadii.topLeft, cornerRadii.topRight),
                AnimatablePair(cornerRadii.bottomRight, cornerRadii.bottomLeft)
            )
        }
        set {
            cornerRadii = PreviewCornerRadii(
                topLeft: newValue.first.first,
                topRight: newValue.first.second,
                bottomRight: newValue.second.first,
                bottomLeft: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard !insetRect.isNull, insetRect.width > 0, insetRect.height > 0 else { return Path() }

        let maxRadius = min(insetRect.width, insetRect.height) / 2
        let tl = min(cornerRadii.topLeft, maxRadius)
        let tr = min(cornerRadii.topRight, maxRadius)
        let br = min(cornerRadii.bottomRight, maxRadius)
        let bl = min(cornerRadii.bottomLeft, maxRadius)

        var path = Path()
        path.move(to: CGPoint(x: insetRect.minX + tl, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX - tr, y: insetRect.minY))
        if tr > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.maxX - tr, y: insetRect.minY + tr),
                radius: tr,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false,
            )
        }
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - br))
        if br > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.maxX - br, y: insetRect.maxY - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false,
            )
        }
        path.addLine(to: CGPoint(x: insetRect.minX + bl, y: insetRect.maxY))
        if bl > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.minX + bl, y: insetRect.maxY - bl),
                radius: bl,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false,
            )
        }
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY + tl))
        if tl > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.minX + tl, y: insetRect.minY + tl),
                radius: tl,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false,
            )
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> WindowTabDropOutlineShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

extension CGRect {
    func alignedToBackingPixels() -> CGRect {
        let scale = (NSScreen.screens
            .max(by: { $0.frame.intersection(self).area < $1.frame.intersection(self).area })?
            .backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        let alignedMinX = (minX * scale).rounded() / scale
        let alignedMinY = (minY * scale).rounded() / scale
        let alignedMaxX = (maxX * scale).rounded() / scale
        let alignedMaxY = (maxY * scale).rounded() / scale
        return CGRect(
            x: alignedMinX,
            y: alignedMinY,
            width: max(alignedMaxX - alignedMinX, 0),
            height: max(alignedMaxY - alignedMinY, 0),
        )
    }

    var area: CGFloat {
        isNull ? 0 : width * height
    }
}
