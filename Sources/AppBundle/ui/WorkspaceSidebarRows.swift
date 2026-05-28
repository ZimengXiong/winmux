import AppKit
import Common
import SwiftUI

// MARK: - Window Row

struct WorkspaceSidebarWindowRow: View {
    enum Style {
        case window
        case tabGroupHeader
        case tabGroupChild
    }

    let title: String
    let badge: String?
    let isFocused: Bool
    let suppressFocusedStyle: Bool
    let rowHeight: CGFloat
    let isHovered: Bool
    let style: Style
    let appBundleIds: [String?]
    let appBundlePaths: [String?]

    private var isTabGroupHeader: Bool { style == .tabGroupHeader }
    private var isTabGroupChild: Bool { style == .tabGroupChild }
    private var isActiveRow: Bool { isFocused && !suppressFocusedStyle }
    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: workspaceSidebarAppIconTextSpacing) {
            appIconStack
            Text(title)
                .font(.system(size: isTabGroupHeader ? 13 : 12.5, weight: isActiveRow ? .semibold : .regular))
                .foregroundStyle(rowTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isTabGroupHeader ? Color.white.opacity(0.50) : Color.white.opacity(0.38))
            }
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, 1)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            rowShape
                .fill(rowBackgroundFill)
            if isHovered {
                rowShape
                    .fill(rowHoverOverlayFill)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var appIconStack: some View {
        if isTabGroupHeader {
            HStack(spacing: -3) {
                ForEach(Array(appIconInputs.prefix(4).enumerated()), id: \.offset) { _, input in
                    appIcon(input)
                }
            }
        } else if let input = appIconInputs.first {
            appIcon(input)
        }
    }

    private var appIconInputs: [(String?, String?)] {
        Array(zip(appBundleIds, appBundlePaths)).filter { $0.0 != nil || $0.1 != nil }
    }

    private func appIcon(_ input: (String?, String?)) -> some View {
        Group {
            if let icon = appIconImage(bundleIdentifier: input.0, bundlePath: input.1) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: workspaceSidebarAppIconSize, height: workspaceSidebarAppIconSize)
                    .cornerRadius(3)
                    .opacity(rowIconOpacity)
            }
        }
    }

    private var rowTextColor: Color {
        if isActiveRow {
            return Color.white.opacity(isTabGroupHeader ? 0.96 : 1)
        }
        if isTabGroupChild {
            return Color.white.opacity(0.58)
        }
        return Color.white.opacity(0.78)
    }

    private var rowIconOpacity: Double {
        isTabGroupChild ? 0.56 : 1
    }

    private var rowBackgroundFill: Color {
        if isActiveRow {
            if isTabGroupHeader {
                return Color.white.opacity(0.14)
            }
            if isTabGroupChild {
                return Color.white.opacity(0.055)
            }
            return Color.white.opacity(0.085)
        }
        return Color.clear
    }

    private var rowHoverOverlayFill: Color {
        if isTabGroupHeader {
            return Color.white.opacity(0.04)
        }
        if isTabGroupChild {
            return Color.white.opacity(0.03)
        }
        return Color.white.opacity(0.045)
    }
}

// MARK: - Drop Preview Row

struct WorkspaceSidebarPreviewRow: View {
    let preview: WorkspaceSidebarDropPreviewViewModel
    let expansionProgress: CGFloat
    let rowHeight: CGFloat
    let expandedContentWidth: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.20))
                Image(systemName: preview.isTabGroup ? "square.stack.3d.up.fill" : "macwindow")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.92))
            }
            .frame(width: 18, height: 18)
            .opacity(0.92)

            Text(preview.label)
                .font(.system(size: 11.2, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(1)
                .opacity(max(expansionProgress, 0.12))
            Spacer(minLength: 0)
            if preview.isTabGroup, preview.windowCount > 1, expansionProgress > 0.72 {
                Text("\(preview.windowCount)")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.09))
                    )
            }
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, 1.5)
        .frame(height: rowHeight + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.105))
                .overlay {
                    RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                        .strokeBorder(
                            Color.accentColor.opacity(0.32),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                        )
                }
        )
        .shadow(color: Color.accentColor.opacity(0.12), radius: 9, y: 2)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }
}
