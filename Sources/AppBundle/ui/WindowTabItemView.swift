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

}
