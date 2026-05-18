import SwiftUI

struct WindowTabItemView: View {
    let tab: WindowTabItemViewModel
    let width: CGFloat
    let height: CGFloat
    let isDragSource: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 6) {
            appIcon(size: 14)

            Text(tab.title)
                .font(.system(size: 12, weight: tab.isActive ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(tabForegroundStyle)
        .padding(.horizontal, 10)
        .frame(width: width, height: height, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .fill(tab.isActive ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .stroke(tabStrokeStyle, lineWidth: 1)
        }
        .opacity(isDragSource ? 0.55 : 1.0)
        .contentShape(Rectangle())
    }

    private var tabForegroundStyle: Color {
        if tab.isActive { return Color.white.opacity(0.96) }
        if isDragSource { return Color.white.opacity(0.80) }
        return Color.white.opacity(isHovered ? 0.78 : 0.68)
    }

    private var tabStrokeStyle: Color {
        if tab.isActive { return Color.white.opacity(0.24) }
        return Color.white.opacity(isHovered ? 0.14 : 0.10)
    }
}
