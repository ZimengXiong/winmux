import AppKit
import Common
import SwiftUI

// MARK: - Window Row

struct WorkspaceSidebarWindowRow: View {
    enum Style {
        case window
        case tabGroupHeader
    }

    let title: String
    let badge: String?
    let isFocused: Bool
    let rowHeight: CGFloat
    let isHovered: Bool
    let style: Style
    let hoverNamespace: Namespace.ID

    private var isTabGroupHeader: Bool { style == .tabGroupHeader }
    private var isActiveRow: Bool { isFocused }
    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: isTabGroupHeader ? 12.5 : 12, weight: isActiveRow ? .semibold : .regular))
                .foregroundStyle(rowTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isTabGroupHeader ? Color.white.opacity(0.64) : Color.white.opacity(0.52))
            }
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, 1.5)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            rowShape
                .fill(rowBackgroundFill)
            if isHovered {
                rowShape
                    .fill(rowHoverOverlayFill)
                    .matchedGeometryEffect(id: "workspace-sidebar-row-hover", in: hoverNamespace)
            }
        }
        .overlay {
            if isActiveRow {
                rowShape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.035),
                                Color.white.opacity(0.00),
                            ],
                            startPoint: .top,
                            endPoint: .bottom,
                        )
                    )
            }
        }
        .overlay {
            if isActiveRow {
                rowShape
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
            }
        }
        .contentShape(Rectangle())
    }

    private var rowTextColor: Color {
        if isActiveRow {
            return Color.white.opacity(isTabGroupHeader ? 0.96 : 1)
        }
        return Color.white.opacity(0.78)
    }

    private var rowBackgroundFill: Color {
        if isActiveRow {
            if isTabGroupHeader {
                return Color.white.opacity(0.14)
            }
            return Color.white.opacity(0.085)
        }
        return Color.clear
    }

    private var rowHoverOverlayFill: Color {
        isTabGroupHeader ? Color.white.opacity(0.04) : Color.white.opacity(0.045)
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
